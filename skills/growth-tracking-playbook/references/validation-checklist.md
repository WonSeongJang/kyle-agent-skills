# Validation Checklist

## Search Console

- property exists
- verification succeeds
- sitemap is submitted
- key URLs can be inspected

## Event collection

- collector endpoint returns success
- sample event is stored
- UTM fields persist correctly
- sensitive raw text is not stored

## Dashboard

- admin login succeeds
- summary endpoint returns data
- KPI cards render
- traffic breakdown shows `source / medium / campaign`

## Short links

- `/go/...` routes return expected redirects
- final destination contains intended UTM fields

## Final smoke test

- one search-facing URL
- one shared URL with UTM
- one admin dashboard login
- one stored event visible in summary
