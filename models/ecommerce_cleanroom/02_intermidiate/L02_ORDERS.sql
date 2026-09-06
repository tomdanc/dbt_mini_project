with step_01_exact_duplicates as (

    select *,
        row_number() over (
        partition by order_id, customer_id, order_date, status, currency, total_amount
        order by order_id
        ) as rn

    from {{ ref('L01_ORDERS') }}

),



step_03_order_ranked as (

    select *,
        row_number() over (
            partition by order_id
            order by case when status = 'cancelled' then 0 else 1 end, status
        ) as order_rn

    from step_01_exact_duplicates
    where rn = 1

),

-- for the negative total
step_04 as (

    select *,
        case when total_amount < 0 then 'negative_total' end as quality_issue


    from step_03_order_ranked

)

select
    order_id,
    customer_id,
    order_date,
    status,
    currency,
     total_amount,

    quality_issue

from step_04
where order_rn = 1