I have SSRS reports with parameters (dates, customerId, region, etc.).
Design:
1) a UI pattern for selecting parameters (validation + presets)
2) a backend contract (DTOs) representing report definitions and parameter metadata
3) an approach for caching report list/metadata
4) an error-handling model (missing params, SSRS down, permission denied)

Ask what the report catalog structure looks like and whether parameters are shared.