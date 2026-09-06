{#
    non_negative -- generic test

    Fails on any value < 0. NULLs pass: 'NULL < 0' evaluates to NULL, so those rows are not
    returned. That is correct -- missing is a separate concern, covered by not_null.
#}
{% test non_negative(model, column_name) %}

select *
from {{ model }}
where {{ column_name }} < 0

{% endtest %}
