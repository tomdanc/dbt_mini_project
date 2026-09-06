with customers_rejected as (

    select
        'L02_CUSTOMERS' as source_table,
        'customer_id'   as key_name,
        customer_id     as key_value,
        reject_reason

    from {{ ref('L02_CUSTOMERS') }}
    where reject_reason is not null

),

products_rejected as (

    select
        'L02_PRODUCTS' as source_table,
        'sku'          as key_name,
        sku            as key_value,
        reject_reason

    from {{ ref('L02_PRODUCTS') }}
    where reject_reason is not null

),

orders_rejected as (

    select
        'L02_ORDERS' as source_table,
        'order_id'   as key_name,
        order_id     as key_value,
        reject_reason

    from {{ ref('L02_ORDERS') }}
    where reject_reason is not null

),

order_items_rejected as (

    select
        'L02_ORDER_ITEMS' as source_table,
        'item_id'         as key_name,
        item_id           as key_value,
        reject_reason

    from {{ ref('L02_ORDER_ITEMS') }}
    where reject_reason is not null

)

select * from customers_rejected
union all
select * from products_rejected
union all
select * from orders_rejected
union all
select * from order_items_rejected