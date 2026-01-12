-- Full rebuild of mzda_ops_db.dbo.mzda_repair_order_record_snapshot from mzda_dms_repair_orders using usp_mzda_service_record_aggregator_used_sale.

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

declare @batch_size int = 10000;

drop table if exists mzda_ops_db.dbo.mzda_repair_order_record_snapshot;

drop table if exists #mzda_vehicle_queue;
select
  v.mzda_vehicle_number,
  v.mzda_manufacture_date,
  row_number() over (order by v.mzda_vehicle_number, v.mzda_manufacture_date) as rn
into
  #mzda_vehicle_queue
from
  (
    select distinct
      mzda_vehicle_number,
      mzda_manufacture_date
    from
      mzda_ops_db.dbo.vw_mzda_service_record_used_sale_input
  ) v;

declare @total int = (select max(rn) from #mzda_vehicle_queue);
declare @start int = 1;

if @total is null
begin
  drop table if exists #mzda_service_record_mzda_vehicles;
  create table #mzda_service_record_mzda_vehicles (
    mzda_vehicle_number varchar(32) not null,
    mzda_manufacture_date date not null
  );

  exec dbo.usp_mzda_service_record_aggregator_used_sale;

  select top (0)
    *
  into
    mzda_ops_db.dbo.mzda_repair_order_record_snapshot
  from
    #mzda_service_record_snapshot_rows;

  drop view if exists mzda_ops_db.dbo.vw_mzda_service_record_used_sale_input;
  return;
end;

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

  if object_id('mzda_ops_db.dbo.mzda_repair_order_record_snapshot', 'U') is null
  begin
    select top (0)
      *
    into
      mzda_ops_db.dbo.mzda_repair_order_record_snapshot
    from
      #mzda_service_record_snapshot_rows;
  end;

  insert into mzda_ops_db.dbo.mzda_repair_order_record_snapshot
  select
    *
  from
    #mzda_service_record_snapshot_rows;

  set @start += @batch_size;
end;

drop view if exists mzda_ops_db.dbo.vw_mzda_service_record_used_sale_input;
