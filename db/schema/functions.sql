create or replace function korniichuk_food.get_statistic()
returns table (
    restaurant_name varchar(100),
    best_product_name varchar(100),
    total_amount numeric(8,2),
    avg_amount numeric(8,2),
    best_user varchar(50)
)
language sql
as $$
    with delivered_orders as materialized (
        select
            o.order_id,
            o.restaurant_id,
            o.total_amount,
            c.login
        from korniichuk_food."order" o
        join korniichuk_food.client c
            on c.client_id = o.client_id
        where o.status = 'доставлен'
    ),
    restaurant_totals as (
        select
            restaurant_id,
            sum(total_amount) as total_amount,
            avg(total_amount) as avg_amount
        from delivered_orders
        group by restaurant_id
    ),
    product_totals as (
        select
            d.restaurant_id,
            p.product_id,
            p.product_name,
            sum(os.quantity) as quantity
        from delivered_orders d
        join korniichuk_food.order_structure os
            on os.order_id = d.order_id
        join korniichuk_food.product p
            on p.product_id = os.product_id
           and p.restaurant_id = d.restaurant_id
        group by d.restaurant_id, p.product_id, p.product_name
    ),
    best_products as (
        select distinct on (restaurant_id)
            restaurant_id,
            product_name
        from product_totals
        order by restaurant_id, quantity desc, random()
    ),
    user_totals as (
        select
            restaurant_id,
            login,
            count(*) as order_count
        from delivered_orders
        group by restaurant_id, login
    ),
    best_users as (
        select distinct on (restaurant_id)
            restaurant_id,
            login
        from user_totals
        order by restaurant_id, order_count desc, random()
    )
    select
        r.restaurant_name,
        bp.product_name as best_product_name,
        rt.total_amount,
        rt.avg_amount,
        bu.login as best_user
    from korniichuk_food.restaurant r
    left join restaurant_totals rt
        on rt.restaurant_id = r.restaurant_id
    left join best_products bp
        on bp.restaurant_id = r.restaurant_id
    left join best_users bu
        on bu.restaurant_id = r.restaurant_id
    order by r.restaurant_name;
$$;
