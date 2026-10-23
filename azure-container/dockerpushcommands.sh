az acr login --name azacreastus001 --expose-token

az acr build --registry azacreastus001 --image fastapi:1.0 .
