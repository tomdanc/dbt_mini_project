select
    customer_id,
    full_name,
    email,
    phone,
    country,
    signup_date

from {{ ref('L02_CUSTOMERS') }}
