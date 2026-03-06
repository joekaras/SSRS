Implement a thin slice in a .NET Framework 4.8 IIS app WITHOUT assuming MVC or Web Forms:

- /login (GET returns HTML form)
- /login (POST validates credentials, sets forms auth cookie)
- /reports (GET lists authorized reports)
- /report/view?id=123 (GET returns a page with iframe)
- iframe src points to /ssrs/?... generated server-side (no direct SSRS host)

Use:
- Forms authentication cookie
- SQL role-based authorization
- audit logging for each report view
- anti-forgery for POST

Provide:
- minimal System.Web handlers (HttpHandler) OR OWIN middleware approach
- web.config auth config
- basic HTML templates
- notes how to later migrate to MVC/WebForms if desired