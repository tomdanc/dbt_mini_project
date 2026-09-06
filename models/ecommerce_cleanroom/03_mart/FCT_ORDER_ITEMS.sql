select
    i.item_id,
    o.order_id,
    p.sku,
    i.quantity,
    i.unit_price,
    i.line_total

from {{ ref('L02_ORDER_ITEMS') }} i

left join {{ ref('FCT_ORDERS') }} o
    on i.order_id = o.order_id

left join {{ ref('DIM_PRODUCTS') }} p
    on i.sku = p.sku