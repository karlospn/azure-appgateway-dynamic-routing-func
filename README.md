# Introduction 
These repo contains an Azure ARM custom provider that allows to add new path rules and listeners to an existing Azure application  gateway.
The custom provider is an Azure Powershell Function.

# How to use

Add these resource inside your ARM template

```javascript

 "resources": [
        {
            "apiVersion": "2018-09-01-preview",
            "type": "Microsoft.CustomProviders/resourceProviders",
            "name": "myCustomProvider",
            "location": "westeurope",
            "properties": {
                "resourceTypes": [
                    {
                        "name": "AddAppGatewayRoutes",
                        "routingType": "Proxy",
                        "endpoint": "ENDPOINT-WHERE-YOU-DEPLOYED-THE-POWERSHELL-AZURE-FUNCTION"
                    }
                ]
            }
        },
        {
            "apiVersion": "2018-09-01-preview",
            "type": "Microsoft.CustomProviders/resourceProviders/AddAppGatewayRoutes",
            "name": "myCustomProvider/AddNewRoute",
            "location": "westeurope",
             "dependsOn": [
                "[resourceId('Microsoft.CustomProviders/resourceProviders/', 'myCustomProvider')]"
            ],
            "properties": {
                "gatewayName": "alb-ase",
                "resGroup": "rg-alb-shared-001",
                "appName": "automation15",
                "protocol": "Http",
                "appServiceHostname": "vytestapppoc2.ase-main.appserviceenvironment.net",
                "pathRulePath": "/aut15/*"
            }
        }
    ],

```

These custom providers need the following properties:

- gatewayName : application gateway name
- resGroup: resource group where the app gateway is deployed
- appName : application name
- protocol : listener protocol
- appServiceHostName: for rewriting host name
- pathRulePath : path route in app gateway
