with step_01_exact_ranked as (

    select *,
        row_number() over (
        partition by item_id, order_id, sku, quantity, unit_price, line_total
        order by item_id
        ) as rn

    from {{ ref('L01_ORDERS_ITEMS') }}

),



-- an item whose order does not survive L02_ORDERS has no parent
step_03_orphan_check as (

    select *
    from step_01_exact_ranked
    where rn = 1
      and quantity is not null
      and quantity > 0
      and order_id in (
          select order_id
          from {{ ref('L02_ORDERS') }}
          where order_id is not null
      )

),
step_04_id_deduplication as (

    select *,
        row_number() over (
            partition by item_id
            order by item_id
        ) as id_rn

    from step_03_orphan_check

)

select
    item_id,
    order_id,
    sku,
    quantity,
    unit_price,
    line_total

from step_04_id_deduplication
where id_rn = 1

