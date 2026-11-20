create or replace procedure korniichuk_food.insert_test_data(value int)
language plpgsql
as $$
declare
    v_client_ids uuid[];
    v_address_ids uuid[] := '{}'::uuid[];
    v_restaurant_ids uuid[];
    v_courier_ids uuid[];
    v_active_courier_ids uuid[];
    v_category_ids uuid[];

    v_client_id uuid;
    v_address_id uuid;
    v_restaurant_id uuid;
    v_courier_id uuid;
    v_category_id uuid;
    v_order_id uuid;

    v_client_index int;
    v_restaurant_index int;
    v_product_index int;
    v_order_index int;
    v_active_courier_count int;

    v_product_count int;
    v_restaurant_product_ids uuid[];
    v_month_start date;
    v_order_timestamp timestamp;
    v_delivery_timestamp timestamp;
    v_review_timestamp timestamp;
    v_month_date date;

    v_coefficient numeric(2, 1);
    v_delivered_count int;
    v_review_type korniichuk_food.review_entity_type;
    v_courier_status korniichuk_food.courier_status;
    v_order_status korniichuk_food.order_status;
    v_dismissal_date date;
    v_month_stats record;
begin
    if value is null or value < 1 then
        raise exception 'value must be greater than zero';
    end if;

    -- Генерируем шесть календарных месяцев: текущий и пять предыдущих.
    v_month_start := date_trunc('month', current_date - interval '5 months')::date;

    truncate table
        korniichuk_food.review,
        korniichuk_food.payment,
        korniichuk_food.order_structure,
        korniichuk_food."order",
        korniichuk_food.courier_pay,
        korniichuk_food.product,
        korniichuk_food.restaurant,
        korniichuk_food.client_address,
        korniichuk_food.client,
        korniichuk_food.address,
        korniichuk_food.courier,
        korniichuk_food.product_category;

    -- BR-11.7: value адресов для ресторанов и value * 4 для клиентов.
    for v_order_index in 1..(value * 5) loop
        insert into korniichuk_food.address (
            address_id,
            street,
            house_number,
            apartment_office
        )
        values (
            exts.uuid_generate_v4(),
            repeat(
                substring(
                    'абвгдеёжзийклмнопрстуфхцчшщъыьэюя',
                    1,
                    greatest(1, ceil(random() * 33)::int)
                ),
                greatest(1, ceil(random() * 3)::int)
            ),
            (1 + floor(random() * 200))::int::text,
            case
                when random() < 0.25 then null
                else (1 + floor(random() * 300))::int::text
            end
        )
        returning address_id into v_address_id;

        -- Сохраняем порядок вставки: первые value адресов принадлежат ресторанам.
        v_address_ids := array_append(v_address_ids, v_address_id);
    end loop;

    -- Категории.
    for v_order_index in 1..value loop
        insert into korniichuk_food.product_category (
            product_category_id,
            product_category_name
        )
        values (
            exts.uuid_generate_v4(),
            repeat(
                substring(
                    'абвгдеёжзийклмнопрстуфхцчшщъыьэюя',
                    1,
                    greatest(1, ceil(random() * 33)::int)
                ),
                greatest(1, ceil(random() * 3)::int)
            )
        )
        returning product_category_id into v_category_id;
    end loop;

    select array_agg(product_category_id order by product_category_id)
    into v_category_ids
    from korniichuk_food.product_category;

    -- Курьеры. Первый курьер гарантированно остаётся активным.
    for v_order_index in 1..value loop
        v_courier_status := case
            when v_order_index = 1
                then 'свободен'::korniichuk_food.courier_status
            else (enum_range(null::korniichuk_food.courier_status))[
                1 + floor(random() * cardinality(
                    enum_range(null::korniichuk_food.courier_status)
                ))::int
            ]
        end;

        insert into korniichuk_food.courier (
            courier_id,
            last_name,
            first_name,
            patronymic,
            phone_number,
            status,
            hire_date,
            dismissal_date,
            coefficient
        )
        values (
            exts.uuid_generate_v4(),
            repeat(
                substring(
                    'абвгдеёжзийклмнопрстуфхцчшщъыьэюя',
                    1,
                    greatest(1, ceil(random() * 33)::int)
                ),
                greatest(1, ceil(random() * 3)::int)
            ),
            repeat(
                substring(
                    'абвгдеёжзийклмнопрстуфхцчшщъыьэюя',
                    1,
                    greatest(1, ceil(random() * 33)::int)
                ),
                greatest(1, ceil(random() * 3)::int)
            ),
            repeat(
                substring(
                    'абвгдеёжзийклмнопрстуфхцчшщъыьэюя',
                    1,
                    greatest(1, ceil(random() * 33)::int)
                ),
                greatest(1, ceil(random() * 3)::int)
            ),
            lpad(
                (
                    floor(random() * 100000)::bigint * 100000
                    + v_order_index
                )::text,
                11,
                '0'
            ),
            v_courier_status,
            current_date - 180,
            case
                when v_courier_status = 'уволен'::korniichuk_food.courier_status
                    then current_date - floor(random() * 180)::int
                else null
            end,
            0.1
        )
        returning courier_id into v_courier_id;
    end loop;

    select array_agg(courier_id order by courier_id)
    into v_courier_ids
    from korniichuk_food.courier;

    select array_agg(courier_id order by courier_id)
    into v_active_courier_ids
    from korniichuk_food.courier
    where status != 'уволен'::korniichuk_food.courier_status;

    v_active_courier_count := cardinality(v_active_courier_ids);

    -- Рестораны используют первые value адресов.
    for v_restaurant_index in 1..value loop
        insert into korniichuk_food.restaurant (
            restaurant_id,
            restaurant_name,
            address_id,
            description,
            work_start,
            work_end,
            inn,
            ogrn,
            settlement_account,
            rating,
            status
        )
        values (
            exts.uuid_generate_v4(),
            repeat(
                substring(
                    'абвгдеёжзийклмнопрстуфхцчшщъыьэюя',
                    1,
                    greatest(1, ceil(random() * 33)::int)
                ),
                greatest(1, ceil(random() * 3)::int)
            ),
            v_address_ids[v_restaurant_index],
            substring(md5(random()::text), 1, greatest(1, ceil(random() * 50)::int)),
            time '08:00',
            time '22:00',
            (
                select string_agg(floor(random() * 10)::int::text, '')
                from generate_series(1, 10)
            ),
            (
                select string_agg(floor(random() * 10)::int::text, '')
                from generate_series(1, 13)
            ),
            (
                select string_agg(floor(random() * 10)::int::text, '')
                from generate_series(1, 18)
            ),
            null,
            (enum_range(null::korniichuk_food.restaurant_status))[
                1 + floor(random() * cardinality(
                    enum_range(null::korniichuk_food.restaurant_status)
                ))::int
            ]
        )
        returning restaurant_id into v_restaurant_id;
    end loop;

    select array_agg(restaurant_id order by restaurant_id)
    into v_restaurant_ids
    from korniichuk_food.restaurant;

    -- Клиенты. Логин и телефон уникальны без вероятностных коллизий.
    for v_client_index in 1..value loop
        insert into korniichuk_food.client (
            client_id,
            login,
            password,
            phone_number
        )
        values (
            exts.uuid_generate_v4(),
            repeat(
                substring(
                    'абвгдеёжзийклмнопрстуфхцчшщъыьэюя',
                    1,
                    greatest(1, ceil(random() * 10)::int)
                ),
                greatest(1, ceil(random() * 2)::int)
            )
            || '_'
            || (100000000 + floor(random() * 900000000))::bigint
            || '_'
            || v_client_index::text,
            md5(random()::text),
            lpad(
                (
                    floor(random() * 100000)::bigint * 100000
                    + v_client_index
                )::text,
                11,
                '0'
            )
        )
        returning client_id into v_client_id;
    end loop;

    select array_agg(client_id order by client_id)
    into v_client_ids
    from korniichuk_food.client;

    -- Каждому клиенту назначаются его четыре адреса.
    for v_client_index in 1..value loop
        for v_order_index in 1..4 loop
            insert into korniichuk_food.client_address (client_id, address_id)
            values (
                v_client_ids[v_client_index],
                v_address_ids[value + (v_client_index - 1) * 4 + v_order_index]
            )
            on conflict (client_id, address_id) do nothing;
        end loop;
    end loop;

    -- По пять блюд на каждый ресторан.
    for v_restaurant_index in 1..value loop
        for v_product_index in 1..5 loop
            insert into korniichuk_food.product (
                product_id,
                product_name,
                product_category_id,
                price,
                restaurant_id,
                photo_url,
                rating,
                status,
                description
            )
            values (
                exts.uuid_generate_v4(),
                repeat(
                    substring(
                        'абвгдеёжзийклмнопрстуфхцчшщъыьэюя',
                        1,
                        greatest(1, ceil(random() * 33)::int)
                    ),
                    greatest(1, ceil(random() * 3)::int)
                ),
                v_category_ids[((v_restaurant_index - 1) % value) + 1],
                round((100 + random() * 900)::numeric, 2),
                v_restaurant_ids[v_restaurant_index],
                case
                    when random() < 0.2 then null
                    else 'https://cdn.foodexpress.ru/img/' || md5(random()::text) || '.jpg'
                end,
                null,
                (enum_range(null::korniichuk_food.product_status))[
                    1 + floor(random() * cardinality(
                        enum_range(null::korniichuk_food.product_status)
                    ))::int
                ],
                substring(md5(random()::text), 1, greatest(1, ceil(random() * 50)::int))
            );
        end loop;
    end loop;

    -- Заказы. Создаём их внутри того же шестимесячного периода,
    -- за который ниже формируются courier_pay.
    for v_order_index in 1..(value * 5) loop
        v_client_index := ((v_order_index - 1) % value) + 1;
        v_restaurant_index := ((v_order_index - 1) % value) + 1;
        v_client_id := v_client_ids[v_client_index];
        v_restaurant_id := v_restaurant_ids[v_restaurant_index];
        v_address_id := v_address_ids[
            value + (v_client_index - 1) * 4 + 1
        ];

        v_order_timestamp := v_month_start::timestamp
            + random() * (
                localtimestamp - v_month_start::timestamp - interval '8 days'
            );

        v_order_status := (enum_range(null::korniichuk_food.order_status))[
            1 + floor(random() * cardinality(
                enum_range(null::korniichuk_food.order_status)
            ))::int
        ];

        -- Дата доставки есть только у доставленных заказов.
        if v_order_status = 'доставлен'::korniichuk_food.order_status then
            v_delivery_timestamp := v_order_timestamp
                + random() * interval '8 days';
        else
            v_delivery_timestamp := null;
        end if;

        -- Выбираем случайного курьера. Если случайно выбран уволенный,
        -- назначаем его только на заказ, оформленный/доставленный до увольнения.
        v_courier_id := v_courier_ids[
            1 + floor(random() * cardinality(v_courier_ids))::int
        ];

        select status, dismissal_date 
        into v_courier_status, v_dismissal_date
        from korniichuk_food.courier
        where courier_id = v_courier_id;

        if v_courier_status = 'уволен'::korniichuk_food.courier_status
           and v_dismissal_date < coalesce(v_delivery_timestamp, v_order_timestamp)::date
        then
            v_courier_id := v_active_courier_ids[
                1 + floor(random() * v_active_courier_count)::int
            ];
        end if;

        insert into korniichuk_food."order" (
            order_id,
            courier_id,
            client_id,
            address_id,
            restaurant_id,
            order_timestamp,
            delivery_timestamp,
            order_amount,
            status,
            pay_status,
            description
        )
        values (
            exts.uuid_generate_v4(),
            v_courier_id,
            v_client_id,
            v_address_id,
            v_restaurant_id,
            v_order_timestamp,
            v_delivery_timestamp,
            1000.00,
            v_order_status,
            'ожидает'::korniichuk_food.order_pay_status,
            substring(md5(random()::text), 1, greatest(1, ceil(random() * 50)::int))
        )
        returning order_id into v_order_id;

        -- Выбираем пять уникальных блюд именно этого ресторана.
        select array_agg(product_id order by random())
        into v_restaurant_product_ids
        from korniichuk_food.product
        where restaurant_id = v_restaurant_id;

        v_product_count := 5;

        for v_product_index in 1..v_product_count loop
            insert into korniichuk_food.order_structure (
                order_id,
                product_id,
                restaurant_id,
                quantity
            )
            values (
                v_order_id,
                v_restaurant_product_ids[v_product_index],
                v_restaurant_id,
                2 + floor(random() * 2)
            );
        end loop;

        update korniichuk_food."order" o
        set order_amount = (
            select round(sum(p.price * os.quantity), 2)
            from korniichuk_food.order_structure os
            join korniichuk_food.product p
              on p.product_id = os.product_id
            where os.order_id = o.order_id
        )
        where o.order_id = v_order_id;

        -- одна успешная попытка оплаты на заказ.
        insert into korniichuk_food.payment (
            payment_id,
            order_id,
            payment_type,
            amount,
            transaction_id,
            transaction_timestamp,
            status
        )
        select
            exts.uuid_generate_v4(),
            v_order_id,
            (enum_range(null::korniichuk_food.payment_type))[
                1 + floor(random() * cardinality(
                    enum_range(null::korniichuk_food.payment_type)
                ))::int
            ],
            o.total_amount,
            'tx_' || v_order_index::text || '_' || md5(exts.uuid_generate_v4()::text),
            o.order_timestamp,
            'успех'::korniichuk_food.payment_status
        from korniichuk_food."order" o
        where o.order_id = v_order_id;

        update korniichuk_food."order" o
        set pay_status = case
            when exists (
                select 1
                from korniichuk_food.payment p
                where p.order_id = o.order_id
                  and p.status = 'успех'::korniichuk_food.payment_status
            ) then 'оплачен'::korniichuk_food.order_pay_status
            when exists (
                select 1
                from korniichuk_food.payment p
                where p.order_id = o.order_id
                  and p.status = 'в_обработке'::korniichuk_food.payment_status
            ) then 'ожидает'::korniichuk_food.order_pay_status
            else 'ошибка'::korniichuk_food.order_pay_status
        end
        where o.order_id = v_order_id;

        -- Отзыв может появиться не раньше создания соответствующего заказа.
        v_review_type := (enum_range(null::korniichuk_food.review_entity_type))[
            1 + floor(random() * cardinality(
                enum_range(null::korniichuk_food.review_entity_type)
            ))::int
        ];

        v_review_timestamp := v_order_timestamp
            + random() * (localtimestamp - v_order_timestamp);

        insert into korniichuk_food.review (
            review_id,
            client_id,
            review_timestamp,
            entity_type,
            entity_id,
            order_id,
            description,
            photo_url,
            rating
        )
        values (
            exts.uuid_generate_v4(),
            v_client_id,
            v_review_timestamp,
            v_review_type,
            case v_review_type
                when 'блюдо'::korniichuk_food.review_entity_type
                    then v_restaurant_product_ids[1]
                when 'ресторан'::korniichuk_food.review_entity_type
                    then v_restaurant_id
                when 'заказ'::korniichuk_food.review_entity_type
                    then v_order_id
            end,
            v_order_id,
            substring(md5(random()::text), 1, greatest(1, ceil(random() * 50)::int)),
            case
                when random() < 0.2 then null
                else 'https://cdn.foodexpress.ru/reviews/' || md5(random()::text) || '.jpg'
            end,
            (1 + floor(random() * 5))::numeric
        );
    end loop;

    -- BR-9.6: агрегированные рейтинги рассчитываются напрямую,
    -- без вызова пользовательских процедур/функций.
    update korniichuk_food.product p
    set rating = (
        select round(avg(r.rating), 2)
        from korniichuk_food.review r
        where r.entity_type = 'блюдо'::korniichuk_food.review_entity_type
          and r.entity_id = p.product_id
    );

    update korniichuk_food.restaurant r
    set rating = (
        select round(avg(rv.rating), 2)
        from korniichuk_food.review rv
        where rv.entity_type = 'ресторан'::korniichuk_food.review_entity_type
          and rv.entity_id = r.restaurant_id
    );

    -- По каждой паре курьер/месяц создаётся строка
    for v_courier_id in
        select unnest(v_courier_ids)
    loop
        select coefficient, status, dismissal_date 
        into v_coefficient, v_courier_status, v_dismissal_date
        from korniichuk_food.courier
        where courier_id = v_courier_id;

        for v_month_stats in
            select
                month_date::date as month_date,
                count(o.order_id)::int as delivered_count,
                coalesce(sum(o.commission), 0) as commission_sum
            from generate_series(
                v_month_start,
                v_month_start + interval '5 months',
                interval '1 month'
            ) as months(month_date)
            left join korniichuk_food."order" o
                on o.courier_id = v_courier_id
               and o.status = 'доставлен'::korniichuk_food.order_status
               and date_trunc('month', o.delivery_timestamp)
                   = date_trunc('month', months.month_date)
            group by month_date
            order by month_date
        loop
            v_month_date := v_month_stats.month_date;
            v_delivered_count := v_month_stats.delivered_count;

            insert into korniichuk_food.courier_pay (
                year,
                month,
                courier_id,
                amount,
                coefficient_used
            )
            select
                extract(year from v_month_date)::int,
                extract(month from v_month_date)::int,
                v_courier_id,
                round(v_month_stats.commission_sum * v_coefficient, 2),
                v_coefficient
            on conflict (year, month, courier_id) do nothing;

            if v_courier_status != 'уволен'::korniichuk_food.courier_status
               or v_dismissal_date is null
               or v_month_date < date_trunc('month', v_dismissal_date)::date
            then
                v_coefficient := case
                    when v_delivered_count <= 150 then 0.1
                    when v_delivered_count <= 250 then 0.2
                    when v_delivered_count <= 500 then 0.3
                    else 0.5
                end;
            end if;
        end loop;

        -- В таблице courier хранится коэффициент уже на следующий месяц.
        -- У уволенного курьера он не обновляется.
        update korniichuk_food.courier
        set coefficient = v_coefficient
        where courier_id = v_courier_id
          and status != 'уволен'::korniichuk_food.courier_status;
    end loop;
end;
$$;


create or replace procedure korniichuk_food.erase_test_data()
language plpgsql
as $$
begin
    truncate table
        korniichuk_food.review,
        korniichuk_food.payment,
        korniichuk_food.order_structure,
        korniichuk_food."order",
        korniichuk_food.courier_pay,
        korniichuk_food.product,
        korniichuk_food.restaurant,
        korniichuk_food.client_address,
        korniichuk_food.client,
        korniichuk_food.address,
        korniichuk_food.courier,
        korniichuk_food.product_category;
end;
$$;


create or replace procedure korniichuk_food.add_product(
    p_name varchar(100),
    p_product_category_id uuid,
    p_price numeric(7, 2),
    p_restaurant_id uuid,
    p_photo_url text,
    p_rating numeric(3, 2),
    p_status korniichuk_food.product_status,
    p_description text
)
language plpgsql
as $$
begin
    if p_restaurant_id is null
       or not exists (
           select 1
           from korniichuk_food.restaurant
           where restaurant_id = p_restaurant_id
       ) then
        raise exception 'Can''t add product: restaurant with id % does not exist', p_restaurant_id
            using errcode = 'foreign_key_violation';
    end if;

    if p_product_category_id is null
       or not exists (
           select 1
           from korniichuk_food.product_category
           where product_category_id = p_product_category_id
       ) then
        raise exception 'Can''t add product: product category with id % does not exist', p_product_category_id
            using errcode = 'foreign_key_violation';
    end if;

    insert into korniichuk_food.product (
        product_name,
        product_category_id,
        price,
        restaurant_id,
        photo_url,
        rating,
        status,
        description
    )
    values (
        p_name,
        p_product_category_id,
        p_price,
        p_restaurant_id,
        p_photo_url,
        p_rating,
        p_status,
        p_description
    );
end;
$$;


create or replace procedure korniichuk_food.courier_salary()
language plpgsql
as $$
declare
    v_month_start date := date_trunc('month', current_date)::date;
    v_next_month_start date := (date_trunc('month', current_date)
        + interval '1 month')::date;
    v_new_coefficient numeric(2, 1);
    v_stats record;
begin
    for v_stats in
        select
            c.courier_id,
            c.coefficient,
            c.status,
            coalesce(cp.coefficient_used, c.coefficient) as applied_coefficient,
            count(o.order_id)::int as delivered_count,
            coalesce(sum(o.commission), 0)::numeric as commission_sum
        from korniichuk_food.courier c
        left join korniichuk_food."order" o
            on o.courier_id = c.courier_id
           and o.status = 'доставлен'
           and o.delivery_timestamp >= v_month_start
           and o.delivery_timestamp < v_next_month_start
        left join korniichuk_food.courier_pay cp
            on cp.courier_id = c.courier_id
           and cp.year = extract(year from current_date)::int
           and cp.month = extract(month from current_date)::int
        group by
            c.courier_id,
            c.coefficient,
            c.status,
            cp.coefficient_used
    loop
        v_new_coefficient := case
            when v_stats.delivered_count <= 150 then 0.1
            when v_stats.delivered_count <= 250 then 0.2
            when v_stats.delivered_count <= 500 then 0.3
            else 0.5
        end;

        insert into korniichuk_food.courier_pay (
            year,
            month,
            courier_id,
            amount,
            coefficient_used
        )
        values (
            extract(year from current_date)::int,
            extract(month from current_date)::int,
            v_stats.courier_id,
            round(
                v_stats.commission_sum * v_stats.applied_coefficient,
                2
            ),
            v_stats.applied_coefficient
        )
        on conflict (year, month, courier_id) do update
        set amount = excluded.amount,
            coefficient_used = excluded.coefficient_used;

        update korniichuk_food.courier
        set coefficient = v_new_coefficient
        where courier_id = v_stats.courier_id
          and status != 'уволен';
    end loop;
end;
$$;
