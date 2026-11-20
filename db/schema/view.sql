create or replace view korniichuk_food.how_much_money (
    year_month,
    sum_no_commission,
    sum_with_commission,
    commission,
    prev_commission,
    commission_diff,
    courier_pay,
    net_profit
) as
with recursive bounds as (
    select
        date_trunc('month', min(o.order_timestamp))::date as first_month,
        date_trunc('month', max(o.order_timestamp))::date as last_month
    from korniichuk_food."order" o
    where o.status = 'доставлен'
),
months (month_start) as (
    select first_month
    from bounds
    where first_month is not null

    union all

    select (m.month_start + interval '1 month')::date
    from months m
    cross join bounds b
    where m.month_start < b.last_month
),
order_totals as (
    select
        date_trunc('month', o.order_timestamp)::date as month_start,
        sum(o.order_amount)::numeric as sum_no_commission,
        sum(o.total_amount)::numeric as sum_with_commission
    from korniichuk_food."order" o
    where o.status = 'доставлен'
    group by date_trunc('month', o.order_timestamp)::date
),
pay_totals as (
    select
        make_date(cp.year, cp.month, 1) as month_start,
        sum(cp.amount)::numeric as courier_pay
    from korniichuk_food.courier_pay cp
    group by make_date(cp.year, cp.month, 1)
),
monthly_totals as (
    select
        m.month_start,
        coalesce(ot.sum_no_commission, 0::numeric) as sum_no_commission,
        coalesce(ot.sum_with_commission, 0::numeric) as sum_with_commission,
        coalesce(ot.sum_with_commission, 0::numeric)
            - coalesce(ot.sum_no_commission, 0::numeric) as commission,
        coalesce(pt.courier_pay, 0::numeric) as courier_pay
    from months m
    left join order_totals ot
        on ot.month_start = m.month_start
    left join pay_totals pt
        on pt.month_start = m.month_start
),
with_previous as (
    select
        mt.*,
        lag(mt.commission) over (order by mt.month_start) as prev_commission
    from monthly_totals mt
)
select
    to_char(wp.month_start, 'YYYY-MM')::text as year_month,
    wp.sum_no_commission,
    wp.sum_with_commission,
    wp.commission,
    wp.prev_commission,
    wp.commission - wp.prev_commission as commission_diff,
    wp.courier_pay,
    wp.commission - wp.courier_pay as net_profit
from with_previous wp;