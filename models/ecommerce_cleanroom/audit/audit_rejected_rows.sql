with missing_customer_id as (

    select
        'L01_CUSTOMERS'       as source_table,
        'customer_id'         as key_name,
        cast(null as varchar) as key_value,
        'missing_customer_id' as reject_reason

    from {{ ref('L01_CUSTOMERS') }}
    where customer_id is null

),

invalid_quantity as (

    select
        'L01_ORDERS_ITEMS' as source_table,
        'item_id'          as key_name,
        item_id            as key_value,
        'invalid_quantity' as reject_reason

    from {{ ref('L01_ORDERS_ITEMS') }}
    where quantity is null
       or quantity <= 0

),

orphan_order as (

    select
        'L01_ORDERS_ITEMS' as source_table,
        'item_id'          as key_name,
        item_id            as key_value,
        'orphan_order'     as reject_reason

    from {{ ref('L01_ORDERS_ITEMS') }}
    where order_id not in (
        select order_id
        from {{ ref('L01_ORDERS') }}
        where order_id is not null
    )

)

select * from missing_customer_id
union all
select * from invalid_quantity
union all
select * from orphan_order