with step_01_exact_duplicates as (

    select *,
        row_number() over (
        partition by order_id, customer_id, order_date, status, currency, total_amount
        order by order_id
        ) as rn

    from {{ ref('L01_ORDERS') }}

),

step_02_flagged as (

    select *,
        case when rn > 1 then 'duplicate_exact' end as reject_reason

    from step_01_exact_duplicates

),

step_03_order_ranked as (

    select *,
        case when reject_reason is null
             then row_number() over (
            partition by reject_reason, order_id
            order by case when status = 'cancelled' then 0 else 1 end, status
             )
        end as order_rn

    from step_02_flagged

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

     case
        when reject_reason is not null then reject_reason
        when order_rn > 1              then 'duplicate_order_id'
    end as reject_reason,

    quality_issue


from step_04