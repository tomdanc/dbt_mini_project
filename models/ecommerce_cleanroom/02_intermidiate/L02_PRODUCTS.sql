with step_01_filtered as (

    select
        sku,
        product_name,
        category,
        --again here
        try_cast(unit_price_czk as decimal(18,2)) as unit_price_czk,
        unit

    from {{ ref('L01_PRODUCTS') }}

),

step_02_sku as (

    select *,
        row_number() over (
            partition by sku
            order by unit_price_czk desc nulls last, product_name
        ) as sku_rn

    from step_01_filtered

)

select
    sku,
    product_name,
    category,

    case when unit_price_czk < 0 then null else unit_price_czk end as unit_price_czk,

    unit,


    case when unit_price_czk < 0 then 'negative_price' end as quality_issue

from step_02_sku
where sku_rn = 1