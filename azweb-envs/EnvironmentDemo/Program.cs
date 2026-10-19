
var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

app.MapGet("/", () =>
{
    var appName =  builder.Configuration.GetValue<string>("APP_NAME")
                  ?? "Local App";

    var environment = builder.Configuration.GetValue<string>("APP_ENV")
                      ?? "Development";

    var message = builder.Configuration.GetValue<string>("WELCOME_MESSAGE")
                  ?? "Hello from .NET!";

    return $"""
        <h1>{message}</h1>
        <p>App Name: {appName}</p>
        <p>Environment: {environment}</p>
        """;
});

app.Run();
