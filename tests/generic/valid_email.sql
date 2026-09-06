{#
    valid_email -- generic test

    Fails on non-NULL values that do not look like an email. NULLs are ignored by design.
    Pattern: something, an @, something, a dot, then a 2+ letter TLD -- with no whitespace or
    second @ anywhere. Deliberately basic; full RFC 5322 validation is not the point.
    DuckDB's regexp_matches is a partial match, which is why the ^ and $ anchors matter.
    In these sources it flags exactly one row: 'marie.urban(at)example.com'.
    Apply at warn severity where the spec says invalid emails survive into the dim.
#}
{% test valid_email(model, column_name) %}

select *
from {{ model }}
where {{ column_name }} is not null
  and not regexp_matches({{ column_name }}, '^[^@\s]+@[^@\s]+\.[a-zA-Z]{2,}$')

{% endtest %}
