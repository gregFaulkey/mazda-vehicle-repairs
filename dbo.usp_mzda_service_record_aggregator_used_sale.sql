create or alter procedure dbo.usp_mzda_service_record_aggregator_used_sale
as
begin
  set nocount on;

  drop table if exists #mzda_service_record_snapshot_rows;

  with
    numbers as (
      select
        top (96)
        row_number() over (order by (select null)) as n
      from
        sys.all_objects
    ),
    mzda_vehicle_list as (
      select distinct
        mzda_vehicle_number,
        mzda_manufacture_date
      from
        #mzda_service_record_mzda_vehicles
    ),
    mzda_repair_order_base as (
      select
        v.mzda_vehicle_number,
        v.mzda_manufacture_date,
        v.as_of_date,
        datefromparts(
          year(v.as_of_date),
          month(v.as_of_date),
          1
        ) as as_of_month_start,
        v.mzda_service_record_string,
        len(v.mzda_service_record_string) as mzda_service_record_len,
        cast(v.source_id as varchar(30)) as source_id
      from
        mzda_ops_db.dbo.vw_mzda_service_record_used_sale_input v
        inner join mzda_vehicle_list a
          on a.mzda_vehicle_number = v.mzda_vehicle_number
          and a.mzda_manufacture_date = v.mzda_manufacture_date
      where
        v.mzda_vehicle_number is not null
        and v.mzda_manufacture_date is not null
        and v.as_of_date is not null
        and v.source_id is not null
        and v.mzda_service_record_string is not null
        and len(v.mzda_service_record_string) > 0
    ),
    mzda_vehicle_anchor as (
      select
        mzda_vehicle_number,
        mzda_manufacture_date,
        max(as_of_date) as as_of_date,
        datefromparts(
          year(max(as_of_date)),
          month(max(as_of_date)),
          1
        ) as run_month_start,
        dateadd(
          month,
          -96,
          datefromparts(year(max(as_of_date)), month(max(as_of_date)), 1)
        ) as window_start
      from
        mzda_repair_order_base
      group by
        mzda_vehicle_number,
        mzda_manufacture_date
    ),
    mzda_repair_order_in_window as (
      select
        b.mzda_vehicle_number,
        b.mzda_manufacture_date,
        b.as_of_date,
        b.as_of_month_start,
        b.mzda_service_record_string,
        b.mzda_service_record_len,
        b.source_id,
        datediff(month, b.as_of_month_start, a.run_month_start) as month_offset
      from
        mzda_repair_order_base b
        inner join mzda_vehicle_anchor a
          on a.mzda_vehicle_number = b.mzda_vehicle_number
          and a.mzda_manufacture_date = b.mzda_manufacture_date
      where
        b.as_of_date >= dateadd(month, 1, a.window_start)
        and b.as_of_date < dateadd(month, 1, a.run_month_start)
    ),
    mzda_repair_order_mzda_statuss as (
      select
        a.mzda_vehicle_number,
        a.mzda_manufacture_date,
        a.as_of_date,
        a.source_id,
        n.n + a.month_offset as mzda_service_record_position,
        cast(substring(a.mzda_service_record_string, n.n, 1) as char(1)) as mzda_service_record_mzda_status
      from
        mzda_repair_order_in_window a
        cross join numbers n
      where
        n.n <= a.mzda_service_record_len
        and n.n + a.month_offset between 1 and 96
    ),
    ranked as (
      select
        mzda_vehicle_number,
        mzda_manufacture_date,
        mzda_service_record_position,
        mzda_service_record_mzda_status,
        as_of_date,
        source_id,
        row_number() over (
          partition by
            mzda_vehicle_number,
            mzda_manufacture_date,
            mzda_service_record_position
          order by
            case when mzda_service_record_mzda_status = 'D' then 0 else 1 end,
            as_of_date desc,
            source_id desc
        ) as rn
      from
        mzda_repair_order_mzda_statuss
      where
        mzda_service_record_mzda_status <> '-'
    ),
    best_mzda_statuss as (
      select
        mzda_vehicle_number,
        mzda_manufacture_date,
        mzda_service_record_position,
        mzda_service_record_mzda_status,
        as_of_date,
        source_id
      from
        ranked
      where
        rn = 1
    ),
    positions as (
      select
        a.mzda_vehicle_number,
        a.mzda_manufacture_date,
        a.as_of_date,
        n.n as mzda_service_record_position
      from
        mzda_vehicle_anchor a
        cross join numbers n
    )
  select
    cast(p.mzda_vehicle_number as varchar(32)) as AccountNumber,
    p.mzda_manufacture_date as dateOpen,
    p.as_of_date as asOfDate,
    cast(string_agg(coalesce(b.mzda_service_record_mzda_status, '-'), '') within group (
      order by
        p.mzda_service_record_position
    ) as varchar(96)) as PHPString,
    max(case when p.mzda_service_record_position = 1 then b.as_of_date end) as mzda_status_date_01,
    max(case when p.mzda_service_record_position = 2 then b.as_of_date end) as mzda_status_date_02,
    max(case when p.mzda_service_record_position = 3 then b.as_of_date end) as mzda_status_date_03,
    max(case when p.mzda_service_record_position = 4 then b.as_of_date end) as mzda_status_date_04,
    max(case when p.mzda_service_record_position = 5 then b.as_of_date end) as mzda_status_date_05,
    max(case when p.mzda_service_record_position = 6 then b.as_of_date end) as mzda_status_date_06,
    max(case when p.mzda_service_record_position = 7 then b.as_of_date end) as mzda_status_date_07,
    max(case when p.mzda_service_record_position = 8 then b.as_of_date end) as mzda_status_date_08,
    max(case when p.mzda_service_record_position = 9 then b.as_of_date end) as mzda_status_date_09,
    max(case when p.mzda_service_record_position = 10 then b.as_of_date end) as mzda_status_date_10,
    max(case when p.mzda_service_record_position = 11 then b.as_of_date end) as mzda_status_date_11,
    max(case when p.mzda_service_record_position = 12 then b.as_of_date end) as mzda_status_date_12,
    max(case when p.mzda_service_record_position = 13 then b.as_of_date end) as mzda_status_date_13,
    max(case when p.mzda_service_record_position = 14 then b.as_of_date end) as mzda_status_date_14,
    max(case when p.mzda_service_record_position = 15 then b.as_of_date end) as mzda_status_date_15,
    max(case when p.mzda_service_record_position = 16 then b.as_of_date end) as mzda_status_date_16,
    max(case when p.mzda_service_record_position = 17 then b.as_of_date end) as mzda_status_date_17,
    max(case when p.mzda_service_record_position = 18 then b.as_of_date end) as mzda_status_date_18,
    max(case when p.mzda_service_record_position = 19 then b.as_of_date end) as mzda_status_date_19,
    max(case when p.mzda_service_record_position = 20 then b.as_of_date end) as mzda_status_date_20,
    max(case when p.mzda_service_record_position = 21 then b.as_of_date end) as mzda_status_date_21,
    max(case when p.mzda_service_record_position = 22 then b.as_of_date end) as mzda_status_date_22,
    max(case when p.mzda_service_record_position = 23 then b.as_of_date end) as mzda_status_date_23,
    max(case when p.mzda_service_record_position = 24 then b.as_of_date end) as mzda_status_date_24,
    max(case when p.mzda_service_record_position = 25 then b.as_of_date end) as mzda_status_date_25,
    max(case when p.mzda_service_record_position = 26 then b.as_of_date end) as mzda_status_date_26,
    max(case when p.mzda_service_record_position = 27 then b.as_of_date end) as mzda_status_date_27,
    max(case when p.mzda_service_record_position = 28 then b.as_of_date end) as mzda_status_date_28,
    max(case when p.mzda_service_record_position = 29 then b.as_of_date end) as mzda_status_date_29,
    max(case when p.mzda_service_record_position = 30 then b.as_of_date end) as mzda_status_date_30,
    max(case when p.mzda_service_record_position = 31 then b.as_of_date end) as mzda_status_date_31,
    max(case when p.mzda_service_record_position = 32 then b.as_of_date end) as mzda_status_date_32,
    max(case when p.mzda_service_record_position = 33 then b.as_of_date end) as mzda_status_date_33,
    max(case when p.mzda_service_record_position = 34 then b.as_of_date end) as mzda_status_date_34,
    max(case when p.mzda_service_record_position = 35 then b.as_of_date end) as mzda_status_date_35,
    max(case when p.mzda_service_record_position = 36 then b.as_of_date end) as mzda_status_date_36,
    max(case when p.mzda_service_record_position = 37 then b.as_of_date end) as mzda_status_date_37,
    max(case when p.mzda_service_record_position = 38 then b.as_of_date end) as mzda_status_date_38,
    max(case when p.mzda_service_record_position = 39 then b.as_of_date end) as mzda_status_date_39,
    max(case when p.mzda_service_record_position = 40 then b.as_of_date end) as mzda_status_date_40,
    max(case when p.mzda_service_record_position = 41 then b.as_of_date end) as mzda_status_date_41,
    max(case when p.mzda_service_record_position = 42 then b.as_of_date end) as mzda_status_date_42,
    max(case when p.mzda_service_record_position = 43 then b.as_of_date end) as mzda_status_date_43,
    max(case when p.mzda_service_record_position = 44 then b.as_of_date end) as mzda_status_date_44,
    max(case when p.mzda_service_record_position = 45 then b.as_of_date end) as mzda_status_date_45,
    max(case when p.mzda_service_record_position = 46 then b.as_of_date end) as mzda_status_date_46,
    max(case when p.mzda_service_record_position = 47 then b.as_of_date end) as mzda_status_date_47,
    max(case when p.mzda_service_record_position = 48 then b.as_of_date end) as mzda_status_date_48,
    max(case when p.mzda_service_record_position = 49 then b.as_of_date end) as mzda_status_date_49,
    max(case when p.mzda_service_record_position = 50 then b.as_of_date end) as mzda_status_date_50,
    max(case when p.mzda_service_record_position = 51 then b.as_of_date end) as mzda_status_date_51,
    max(case when p.mzda_service_record_position = 52 then b.as_of_date end) as mzda_status_date_52,
    max(case when p.mzda_service_record_position = 53 then b.as_of_date end) as mzda_status_date_53,
    max(case when p.mzda_service_record_position = 54 then b.as_of_date end) as mzda_status_date_54,
    max(case when p.mzda_service_record_position = 55 then b.as_of_date end) as mzda_status_date_55,
    max(case when p.mzda_service_record_position = 56 then b.as_of_date end) as mzda_status_date_56,
    max(case when p.mzda_service_record_position = 57 then b.as_of_date end) as mzda_status_date_57,
    max(case when p.mzda_service_record_position = 58 then b.as_of_date end) as mzda_status_date_58,
    max(case when p.mzda_service_record_position = 59 then b.as_of_date end) as mzda_status_date_59,
    max(case when p.mzda_service_record_position = 60 then b.as_of_date end) as mzda_status_date_60,
    max(case when p.mzda_service_record_position = 61 then b.as_of_date end) as mzda_status_date_61,
    max(case when p.mzda_service_record_position = 62 then b.as_of_date end) as mzda_status_date_62,
    max(case when p.mzda_service_record_position = 63 then b.as_of_date end) as mzda_status_date_63,
    max(case when p.mzda_service_record_position = 64 then b.as_of_date end) as mzda_status_date_64,
    max(case when p.mzda_service_record_position = 65 then b.as_of_date end) as mzda_status_date_65,
    max(case when p.mzda_service_record_position = 66 then b.as_of_date end) as mzda_status_date_66,
    max(case when p.mzda_service_record_position = 67 then b.as_of_date end) as mzda_status_date_67,
    max(case when p.mzda_service_record_position = 68 then b.as_of_date end) as mzda_status_date_68,
    max(case when p.mzda_service_record_position = 69 then b.as_of_date end) as mzda_status_date_69,
    max(case when p.mzda_service_record_position = 70 then b.as_of_date end) as mzda_status_date_70,
    max(case when p.mzda_service_record_position = 71 then b.as_of_date end) as mzda_status_date_71,
    max(case when p.mzda_service_record_position = 72 then b.as_of_date end) as mzda_status_date_72,
    max(case when p.mzda_service_record_position = 73 then b.as_of_date end) as mzda_status_date_73,
    max(case when p.mzda_service_record_position = 74 then b.as_of_date end) as mzda_status_date_74,
    max(case when p.mzda_service_record_position = 75 then b.as_of_date end) as mzda_status_date_75,
    max(case when p.mzda_service_record_position = 76 then b.as_of_date end) as mzda_status_date_76,
    max(case when p.mzda_service_record_position = 77 then b.as_of_date end) as mzda_status_date_77,
    max(case when p.mzda_service_record_position = 78 then b.as_of_date end) as mzda_status_date_78,
    max(case when p.mzda_service_record_position = 79 then b.as_of_date end) as mzda_status_date_79,
    max(case when p.mzda_service_record_position = 80 then b.as_of_date end) as mzda_status_date_80,
    max(case when p.mzda_service_record_position = 81 then b.as_of_date end) as mzda_status_date_81,
    max(case when p.mzda_service_record_position = 82 then b.as_of_date end) as mzda_status_date_82,
    max(case when p.mzda_service_record_position = 83 then b.as_of_date end) as mzda_status_date_83,
    max(case when p.mzda_service_record_position = 96 then b.as_of_date end) as mzda_status_date_96,
    max(case when p.mzda_service_record_position = 1 then b.source_id end) as source_id_01,
    max(case when p.mzda_service_record_position = 2 then b.source_id end) as source_id_02,
    max(case when p.mzda_service_record_position = 3 then b.source_id end) as source_id_03,
    max(case when p.mzda_service_record_position = 4 then b.source_id end) as source_id_04,
    max(case when p.mzda_service_record_position = 5 then b.source_id end) as source_id_05,
    max(case when p.mzda_service_record_position = 6 then b.source_id end) as source_id_06,
    max(case when p.mzda_service_record_position = 7 then b.source_id end) as source_id_07,
    max(case when p.mzda_service_record_position = 8 then b.source_id end) as source_id_08,
    max(case when p.mzda_service_record_position = 9 then b.source_id end) as source_id_09,
    max(case when p.mzda_service_record_position = 10 then b.source_id end) as source_id_10,
    max(case when p.mzda_service_record_position = 11 then b.source_id end) as source_id_11,
    max(case when p.mzda_service_record_position = 12 then b.source_id end) as source_id_12,
    max(case when p.mzda_service_record_position = 13 then b.source_id end) as source_id_13,
    max(case when p.mzda_service_record_position = 14 then b.source_id end) as source_id_14,
    max(case when p.mzda_service_record_position = 15 then b.source_id end) as source_id_15,
    max(case when p.mzda_service_record_position = 16 then b.source_id end) as source_id_16,
    max(case when p.mzda_service_record_position = 17 then b.source_id end) as source_id_17,
    max(case when p.mzda_service_record_position = 18 then b.source_id end) as source_id_18,
    max(case when p.mzda_service_record_position = 19 then b.source_id end) as source_id_19,
    max(case when p.mzda_service_record_position = 20 then b.source_id end) as source_id_20,
    max(case when p.mzda_service_record_position = 21 then b.source_id end) as source_id_21,
    max(case when p.mzda_service_record_position = 22 then b.source_id end) as source_id_22,
    max(case when p.mzda_service_record_position = 23 then b.source_id end) as source_id_23,
    max(case when p.mzda_service_record_position = 24 then b.source_id end) as source_id_24,
    max(case when p.mzda_service_record_position = 25 then b.source_id end) as source_id_25,
    max(case when p.mzda_service_record_position = 26 then b.source_id end) as source_id_26,
    max(case when p.mzda_service_record_position = 27 then b.source_id end) as source_id_27,
    max(case when p.mzda_service_record_position = 28 then b.source_id end) as source_id_28,
    max(case when p.mzda_service_record_position = 29 then b.source_id end) as source_id_29,
    max(case when p.mzda_service_record_position = 30 then b.source_id end) as source_id_30,
    max(case when p.mzda_service_record_position = 31 then b.source_id end) as source_id_31,
    max(case when p.mzda_service_record_position = 32 then b.source_id end) as source_id_32,
    max(case when p.mzda_service_record_position = 33 then b.source_id end) as source_id_33,
    max(case when p.mzda_service_record_position = 34 then b.source_id end) as source_id_34,
    max(case when p.mzda_service_record_position = 35 then b.source_id end) as source_id_35,
    max(case when p.mzda_service_record_position = 36 then b.source_id end) as source_id_36,
    max(case when p.mzda_service_record_position = 37 then b.source_id end) as source_id_37,
    max(case when p.mzda_service_record_position = 38 then b.source_id end) as source_id_38,
    max(case when p.mzda_service_record_position = 39 then b.source_id end) as source_id_39,
    max(case when p.mzda_service_record_position = 40 then b.source_id end) as source_id_40,
    max(case when p.mzda_service_record_position = 41 then b.source_id end) as source_id_41,
    max(case when p.mzda_service_record_position = 42 then b.source_id end) as source_id_42,
    max(case when p.mzda_service_record_position = 43 then b.source_id end) as source_id_43,
    max(case when p.mzda_service_record_position = 44 then b.source_id end) as source_id_44,
    max(case when p.mzda_service_record_position = 45 then b.source_id end) as source_id_45,
    max(case when p.mzda_service_record_position = 46 then b.source_id end) as source_id_46,
    max(case when p.mzda_service_record_position = 47 then b.source_id end) as source_id_47,
    max(case when p.mzda_service_record_position = 48 then b.source_id end) as source_id_48,
    max(case when p.mzda_service_record_position = 49 then b.source_id end) as source_id_49,
    max(case when p.mzda_service_record_position = 50 then b.source_id end) as source_id_50,
    max(case when p.mzda_service_record_position = 51 then b.source_id end) as source_id_51,
    max(case when p.mzda_service_record_position = 52 then b.source_id end) as source_id_52,
    max(case when p.mzda_service_record_position = 53 then b.source_id end) as source_id_53,
    max(case when p.mzda_service_record_position = 54 then b.source_id end) as source_id_54,
    max(case when p.mzda_service_record_position = 55 then b.source_id end) as source_id_55,
    max(case when p.mzda_service_record_position = 56 then b.source_id end) as source_id_56,
    max(case when p.mzda_service_record_position = 57 then b.source_id end) as source_id_57,
    max(case when p.mzda_service_record_position = 58 then b.source_id end) as source_id_58,
    max(case when p.mzda_service_record_position = 59 then b.source_id end) as source_id_59,
    max(case when p.mzda_service_record_position = 60 then b.source_id end) as source_id_60,
    max(case when p.mzda_service_record_position = 61 then b.source_id end) as source_id_61,
    max(case when p.mzda_service_record_position = 62 then b.source_id end) as source_id_62,
    max(case when p.mzda_service_record_position = 63 then b.source_id end) as source_id_63,
    max(case when p.mzda_service_record_position = 64 then b.source_id end) as source_id_64,
    max(case when p.mzda_service_record_position = 65 then b.source_id end) as source_id_65,
    max(case when p.mzda_service_record_position = 66 then b.source_id end) as source_id_66,
    max(case when p.mzda_service_record_position = 67 then b.source_id end) as source_id_67,
    max(case when p.mzda_service_record_position = 68 then b.source_id end) as source_id_68,
    max(case when p.mzda_service_record_position = 69 then b.source_id end) as source_id_69,
    max(case when p.mzda_service_record_position = 70 then b.source_id end) as source_id_70,
    max(case when p.mzda_service_record_position = 71 then b.source_id end) as source_id_71,
    max(case when p.mzda_service_record_position = 72 then b.source_id end) as source_id_72,
    max(case when p.mzda_service_record_position = 73 then b.source_id end) as source_id_73,
    max(case when p.mzda_service_record_position = 74 then b.source_id end) as source_id_74,
    max(case when p.mzda_service_record_position = 75 then b.source_id end) as source_id_75,
    max(case when p.mzda_service_record_position = 76 then b.source_id end) as source_id_76,
    max(case when p.mzda_service_record_position = 77 then b.source_id end) as source_id_77,
    max(case when p.mzda_service_record_position = 78 then b.source_id end) as source_id_78,
    max(case when p.mzda_service_record_position = 79 then b.source_id end) as source_id_79,
    max(case when p.mzda_service_record_position = 80 then b.source_id end) as source_id_80,
    max(case when p.mzda_service_record_position = 81 then b.source_id end) as source_id_81,
    max(case when p.mzda_service_record_position = 82 then b.source_id end) as source_id_82,
    max(case when p.mzda_service_record_position = 83 then b.source_id end) as source_id_83,
    max(case when p.mzda_service_record_position = 96 then b.source_id end) as source_id_96
  into
    #mzda_service_record_snapshot_rows
  from
    positions p
    left join best_mzda_statuss b
      on b.mzda_vehicle_number = p.mzda_vehicle_number
      and b.mzda_manufacture_date = p.mzda_manufacture_date
      and b.mzda_service_record_position = p.mzda_service_record_position
  group by
    p.mzda_vehicle_number,
    p.mzda_manufacture_date,
    p.as_of_date
  having
    max(case when b.mzda_service_record_mzda_status is not null then 1 else 0 end) = 1;
end;
