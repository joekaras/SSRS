Write a C# (.NET Framework 4.8) service that generates SSRS embed URLs safely.

Constraints:
- Only allow report paths from an allowlist in DB
- Only allow known parameters per report (allowlist)
- Validate parameter types (date range, ints, enums)
- Encode values safely and prevent SSRF/open redirect style issues
- Output URL suitable for iframe embedding via our reverse-proxy path (/ssrs-proxy/...)

Deliver:
- C# class (e.g., SsrsUrlBuilder)
- DTO representing a report request
- Validation errors model
- Example usage from controller
- Unit tests outline