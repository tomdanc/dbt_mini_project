with numbered as (

    select *,
        row_number() over (
            partition by customer_id, full_name, email, phone, country, signup_date
            order by customer_id
        ) as rn

    from {{ ref('L01_CUSTOMERS') }}
),

id_deduplication as (

    select *,
        row_number() over (
            partition by customer_id
            order by customer_id
        ) as id_rn

    from numbered
    where rn = 1
      and customer_id is not null

)


select
    customer_id,
    full_name,
    email,
    phone,
    country,
    signup_date

    from id_deduplication
    where id_rn = 1






