with step_01_exact_ranked as (

    select *,
        row_number() over (
        partition by item_id, order_id, sku, quantity, unit_price, line_total
        order by item_id
        ) as rn

    from {{ ref('L01_ORDERS_ITEMS') }}

),

step_02_flagged as (

    select *,
        case
            when rn > 1                            then 'duplicate_exact'
            when quantity is null or quantity <= 0 then 'invalid_quantity'
        end as reject_reason

    from step_01_exact_ranked

),

-- an item whose order does not survive L02_ORDERS has no parent
step_03_orphan_check as (

    select *,
        case when order_id not in (
        select order_id
         from {{ ref('L02_ORDERS') }}
            where reject_reason is null
              and order_id is not null
        ) then 1 end as is_orphan

    from step_02_flagged

)

select
    item_id,
    order_id,
    sku,
    quantity,
    unit_price,
    line_total,

    -- this one is still flagging for the wrong id edge case
    case
        when reject_reason is not null then reject_reason
        when is_orphan = 1             then 'orphan_order'
    end as reject_reason

from step_03_orphan_check

