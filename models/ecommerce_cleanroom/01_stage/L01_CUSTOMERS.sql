SELECT
    --trimming and cleaning all of the columns
    IFNULL(customer_id, null) as customer_id,
    NULLIF(TRIM(full_name),'') as full_name,
    NULLIF(LOWER(REPLACE(TRIM(email), '(at)', '@')), '') as email,
    case
        when nullif(trim(phone), '') is null then null
        else
        case
            when regexp_replace(trim(phone), '[^0-9]', '', 'g') = '' then null
            when regexp_replace(trim(phone), '[^0-9]', '', 'g') like '420%' then '+' || regexp_replace(trim(phone), '[^0-9]', '', 'g')
            when regexp_replace(trim(phone), '[^0-9]', '', 'g') like '00420%' then '+' || substr(regexp_replace(trim(phone), '[^0-9]', '', 'g'), 3)
            when regexp_replace(trim(phone), '[^0-9]', '', 'g') like '00%' then '+' || substr(regexp_replace(trim(phone), '[^0-9]', '', 'g'), 3)
            when regexp_replace(trim(phone), '[^0-9]', '', 'g') like '0%' then '+' || '420' || substr(regexp_replace(trim(phone), '[^0-9]', '', 'g'), 2)
        else '+' || '420' || regexp_replace(trim(phone), '[^0-9]', '', 'g')
        end
    end as phone, -- regex here as welll
    case lower(trim(country))
        when 'cz' then 'CZ'
        when 'czechia' then 'CZ'
        when 'czech republic' then 'CZ'
        when 'sk' then 'SK'
        when 'slovakia' then 'SK'
        when 'de' then 'DE'
        when 'germany' then 'DE'
        when 'pl' then 'PL'
        when 'poland' then 'PL'
        when 'at' then 'AT'
        when 'austria' then 'AT'
        else null
    end as country,
    try_strptime(regexp_replace(trim(signup_date), '^(\d{1,2})[./-](\d{1,2})[./-](\d{4})$', '\3-\2-\1'), '%Y-%m-%d') as signup_date

FROM 
    {{source('warehouse' ,'raw_customers')}}

UNION ALL

SELECT
    --trimming and cleaning all of the columns
    IFNULL(customer_id, null) as customer_id,
    NULLIF(TRIM(full_name),'') as full_name,
    NULLIF(LOWER(REPLACE(TRIM(email), '(at)', '@')), '') as email,
    case
        when nullif(trim(phone), '') is null then null
        else
        case
            when regexp_replace(trim(phone), '[^0-9]', '', 'g') = '' then null
            when regexp_replace(trim(phone), '[^0-9]', '', 'g') like '420%' then '+' || regexp_replace(trim(phone), '[^0-9]', '', 'g')
            when regexp_replace(trim(phone), '[^0-9]', '', 'g') like '00420%' then '+' || substr(regexp_replace(trim(phone), '[^0-9]', '', 'g'), 3)
            when regexp_replace(trim(phone), '[^0-9]', '', 'g') like '00%' then '+' || substr(regexp_replace(trim(phone), '[^0-9]', '', 'g'), 3)
            when regexp_replace(trim(phone), '[^0-9]', '', 'g') like '0%' then '+' || '420' || substr(regexp_replace(trim(phone), '[^0-9]', '', 'g'), 2)
        else '+' || '420' || regexp_replace(trim(phone), '[^0-9]', '', 'g')
        end
    end as phone, -- regex here as welll
    case lower(trim(country))
        when 'cz' then 'CZ'
        when 'czechia' then 'CZ'
        when 'czech republic' then 'CZ'
        when 'sk' then 'SK'
        when 'slovakia' then 'SK'
        when 'de' then 'DE'
        when 'germany' then 'DE'
        when 'pl' then 'PL'
        when 'poland' then 'PL'
        when 'at' then 'AT'
        when 'austria' then 'AT'
        else null
    end as country,
    try_strptime(regexp_replace(trim(signup_date), '^(\d{1,2})[./-](\d{1,2})[./-](\d{4})$', '\3-\2-\1'), '%Y-%m-%d') as signup_date

FROM 
    {{source('warehouse' ,'raw_customers_day2')}} 