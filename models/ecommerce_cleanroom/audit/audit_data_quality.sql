-- poterbujju vyflagocvat (email) kdyz odrastanim duplicity tak u toho customer tak tam bude jeden email a potebuju to flaggnout nekym zpusobem a odstranit z toho custom,

SELECT 
    case when unit_price < 0 then null else unit_price end as unit_price,


FROM 
    from {{ ref('L01_CUSTOMERS') }}