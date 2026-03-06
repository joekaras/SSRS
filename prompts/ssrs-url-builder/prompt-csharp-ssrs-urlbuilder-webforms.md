Write a .NET Framework 4.8 C# class that generates a safe proxied SSRS iframe URL.

Inputs:
- current authenticated user (userId)
- reportId
- raw UI parameters (Name->Value)

Server-side steps:
- verify user authorized for reportId via SQL
- read ssrsPath for reportId from DB
- read allowed parameters for reportId from DB
- validate each parameter by type (DateTime, int, enum, string length)
- reject unexpected parameter names
- build proxied URL: /ssrs/Pages/ReportViewer.aspx? (or correct SSRS viewer path) with encoded query string
- return either (success URL) or (validation errors)

Deliver:
- DTOs (ReportRequest, ValidationError)
- SsrsUrlBuilder class
- example usage in reportview.aspx.cs that sets iframe.Src
- unit-test case list