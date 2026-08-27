# Validation Checklist

## Access

- admin auth blocks non-admins
- summary endpoint returns 200 after auth

## Events

- landing event stores
- success event stores
- failure event stores
- UTM fields persist

## Dashboard

- KPI cards render
- traffic table shows `source / medium / campaign`
- failure table renders
- export works

## Search Console

- property exists
- sitemap is submitted
- CSV import succeeds if used

## Final condition

Operators can answer:

- where users came from
- where they dropped off
- why they failed

without querying raw data manually.
