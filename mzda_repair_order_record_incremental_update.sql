-- Incremental update for mzda_ops_db.dbo.mzda_repair_order_record_snapshot using usp_mzda_service_record_aggregator_used_sale.

drop view if exists mzda_ops_db.dbo.vw_mzda_service_record_used_sale_input;
GO

create view mzda_ops_db.dbo.vw_mzda_service_record_used_sale_input
as
select
  cast(a.mzda_vin_num as varchar(32)) as mzda_vehicle_number,
  cast(a.mzda_manufacture_date as date) as mzda_manufacture_date,
  cast(a.mzda_event_date as date) as as_of_date,
  a.mzda_service_record_warranty_prd_mzda_service_log as mzda_service_record_string,
  cast(a.mzda_repair_order_id as varchar(30)) as source_id
from
  mzda_ops_db.dbo.mzda_dms_repair_orders a
where
  a.mzda_vin_num is not null
  and a.mzda_manufacture_date is not null
  and a.mzda_event_date is not null
  and a.mzda_repair_order_id is not null
  and a.mzda_service_record_warranty_prd_mzda_service_log is not null
  and len(a.mzda_service_record_warranty_prd_mzda_service_log) > 0;
GO

set nocount on;

if object_id('mzda_ops_db.dbo.mzda_repair_order_record_snapshot', 'U') is null
begin
  drop view if exists mzda_ops_db.dbo.vw_mzda_service_record_used_sale_input;
  throw 50000, 'mzda_ops_db.dbo.mzda_repair_order_record_snapshot does not exist. Run mzda_repair_order_record_full_build.sql first.', 1;
end;

declare @batch_size int = 10000;

drop table if exists #mzda_vehicles_to_refresh;

with
  source_max as (
    select
      mzda_vehicle_number,
      mzda_manufacture_date,
      max(as_of_date) as max_as_of_date
    from
      mzda_ops_db.dbo.vw_mzda_service_record_used_sale_input
    group by
      mzda_vehicle_number,
      mzda_manufacture_date
  )
select
  s.mzda_vehicle_number,
  s.mzda_manufacture_date
into
  #mzda_vehicles_to_refresh
from
  source_max s
  left join mzda_ops_db.dbo.mzda_repair_order_record_snapshot snap
    on snap.AccountNumber = s.mzda_vehicle_number
    and snap.dateOpen = s.mzda_manufacture_date
where
  s.max_as_of_date > isnull(snap.asOfDate, '19000101');

if not exists (select 1 from #mzda_vehicles_to_refresh)
begin
  drop view if exists mzda_ops_db.dbo.vw_mzda_service_record_used_sale_input;
  return;
end;

drop table if exists #mzda_vehicle_queue;
select
  mzda_vehicle_number,
  mzda_manufacture_date,
  row_number() over (order by mzda_vehicle_number, mzda_manufacture_date) as rn
into
  #mzda_vehicle_queue
from
  #mzda_vehicles_to_refresh;

declare @total int = (select max(rn) from #mzda_vehicle_queue);
declare @start int = 1;

while @start <= @total
begin
  drop table if exists #mzda_service_record_mzda_vehicles;

  select
    mzda_vehicle_number,
    mzda_manufacture_date
  into
    #mzda_service_record_mzda_vehicles
  from
    #mzda_vehicle_queue
  where
    rn between @start and @start + @batch_size - 1;

  exec dbo.usp_mzda_service_record_aggregator_used_sale;

  delete snap
  from
    mzda_ops_db.dbo.mzda_repair_order_record_snapshot snap
    inner join #mzda_service_record_mzda_vehicles a
      on a.mzda_vehicle_number = snap.AccountNumber
      and a.mzda_manufacture_date = snap.dateOpen;

  insert into mzda_ops_db.dbo.mzda_repair_order_record_snapshot
  select
    *
  from
    #mzda_service_record_snapshot_rows;

  set @start += @batch_size;
end;

drop view if exists mzda_ops_db.dbo.vw_mzda_service_record_used_sale_input;
