const jsonString = `{
    "services": [
        {
            "ServiceName": "service 1",
            "codeSN": "TST",
            "codeJSON": "IA1"
        },
		{
            "ServiceName": "service 2",
            "codeSN": "SOS",
            "codeJSON": "SOS"
        },
		{
            "ServiceName": "service 3",
            "codeSN": "xyz",
            "codeJSON": "xyz"
        },
		{
            "ServiceName": "service 4",
            "codeSN": "AZC",
            "codeJSON": "ASC"
        }
    ]
}`;

// This code will be in vRealize Orchestrator, which does not have access to all javascript functions. 
var jsonObject = JSON.parse(jsonString);
// Loop through the jsonObject and create a list of any service, the codeSN and codeJSON where codeSN is not equal to codeJSON
var services = jsonObject.services;
var mismatchedServices = [];

for (var i = 0; i < services.length; i++) {
    var service = services[i];
    if (service.codeSN.toLowerCase() != service.codeJSON.toLowerCase()) {
        mismatchedServices.push(service);
    }
}

console.log(mismatchedServices)
