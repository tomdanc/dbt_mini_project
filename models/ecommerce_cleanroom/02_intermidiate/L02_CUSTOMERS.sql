with numbered as (

    select *,
        row_number() over (
            partition by customer_id, full_name, email, phone, country, signup_date
            order by customer_id
        ) as rn

    from {{ ref('L01_CUSTOMERS') }}
),

flagged as (

    select *,
        case
            when customer_id is null then 'missing_customer_id'
            when rn > 1              then 'duplicate_exact'
        end as reject_reason

    from numbered

)

select
    customer_id,
    full_name,
    email,
    phone,
    country,
    signup_date,
    
    reject_reason

from flagged




