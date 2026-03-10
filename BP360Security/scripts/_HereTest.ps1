$ServiceAccount = 'DOMAIN\svc'
$grantSql = @"
USE [UserAccounts];
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'$ServiceAccount')
    CREATE USER [$ServiceAccount] FOR LOGIN [$ServiceAccount];
IF NOT EXISTS (SELECT 1 FROM sys.database_permissions dp
    JOIN sys.objects o ON dp.major_id = o.object_id
    JOIN sys.database_principals pr ON dp.grantee_principal_id = pr.principal_id
    WHERE pr.name = N'$ServiceAccount' AND o.name = 'LookupUser' AND dp.permission_name = 'EXECUTE')
BEGIN
    GRANT EXECUTE ON dbo.LookupUser   TO [$ServiceAccount];
    GRANT EXECUTE ON dbo.RegisterUser TO [$ServiceAccount];
END
"@
Write-Host "Parsed OK. SQL length: $($grantSql.Length)"
