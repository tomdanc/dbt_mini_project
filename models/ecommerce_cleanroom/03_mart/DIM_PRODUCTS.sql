select
    sku,
    product_name,
    category,
    unit_price_czk, --tohle nepratri do dim table (chci tam udelat tabulku navic pro tohlencto)
    unit --tohle nepratri do dim table (chci tam udelat tabulku navic pro tohlencto)

from {{ ref('L02_PRODUCTS') }}
