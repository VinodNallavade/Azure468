dotnet publish -c Release -o ./publish

Compress-Archive -Path ./publish/* `
  -DestinationPath ./app.zip -Force