---
layout: post
title: "Trigger Azure DevOps Pipeline using a Webhook"
date: 2022-09-06 14:00:00 -0000
categories: [Azure DevOps]
tags: [Azure, Azure DevOps]
img_path: /assets/img/2022-09-06-trigger-azure-devops-pipeline-using-a-webhook/
---

I have always wanted to learn a bit of Python, so I set out to do a project in Django where I have a form that I can fill out and when submitted it will start an Azure DevOps pipeline and provide the data from the form as parameters.

Working with customers using ServiceNow, Jira, etc., it can be a useful tool when trying to automate tasks in Azure. Maybe you want to fully automate your landing zone deployment using a service request form with approvals, or you want to allow developers to be able to order a VM or public IP?

# The order of things

The only reliable way of getting this to work for me has been by configuring the different resources in a specific order.

- Create a service connection of type incoming webhook
- Create pipeline – do not use an existing one, instead copy everything from an existing to a new
- Configure the webhook resource in the pipeline
- Assign the service connection permissions to the pipeline

If you get an error it will most likely state that it can’t find a webhook with the given name.

![trigger-error](trigger-error.png)

# Create incoming webhook

Let’s start by creating the incoming webhook.

1. In Azure DevOps, go to **Project Settings -> Service connections** and select **New service connection**
![new-service-connection](new-service-connection.png)
2. Scroll down and select **Incoming WebHook**
3. Fill in the required information:
    1. Webhook name: Used in pipeline and also when triggering the pipeline using a POST request
    2. Secret: Something secure, we don’t want everyone to be able to use our webhook
    3. Http header: Anything you want
    4. Service connection name: Something descriptive, will also be used in the pipeline
    5. Security: Untick **Grant access permissions to all pipelines**

    ![service-connection-details](service-connection-details.png)

# Create pipeline

Next up is to create the pipeline and configure the webhook resource inside it.

1. Go to **Pipelines -> New pipeline -> Azure Repos Git**
2. Select your repository
3. Select **Starter pipeline**

The below pipeline code will disable other triggers to make sure we only trigger the pipeline using our webhook.

The resource section references our webhook name and service connection name.

We can also see that two parameters are referenced. They’re picked up from the payload sent with the POST request when triggering the webhook. More on that later!

```yaml
# Disable non-webhook triggers
trigger: none
pr: none

# Webhook resource that triggers pipeline
resources:
  webhooks:
    - webhook: WebookDemoTrigger           ### Webhook name
      connection: WebhookDemoConnection    ### Incoming webhook service connection name

pool:
  vmImage: ubuntu-latest

steps:
- task: PowerShell@2
  inputs:
    targetType: inline
    script: |
      # Write parameters from webhook payload to console
      {% raw %}Write-Host ${{ parameters.WebookDemoTrigger.app_name }}
      Write-Host ${{ parameters.WebookDemoTrigger.environment }} {% endraw %}
```

# Assign permissions to the pipeline

We’re done with steps 1-3, but since we unticked the box that gives the service connection permissions to all pipelines, we need to make sure we give it access to our pipeline.

Go to your service connection (the incoming webhook), select the three dots and **Security**.

![service-connection-permissions](service-connection-permissions.png)

Under **Pipeline permissions**, select the + sign and add your newly created pipeline.

![service-connection-permissions-add](service-connection-permissions-add.png)

# Fire in the hole!

We should now be able to trigger the webhook using our preferred method. I’ll provide examples for PowerShell and Python.

**PowerShell (stolen from GitHub, credit to Igor Abade)**

The uri requires us to fill in our Azure DevOps organization name, and the name of the incoming webhook (WebhookDemoTrigger).

In **$Body** we can define the data sent in the payload, this is what we can later reference using: \
{% raw %}${{ parameters.. }}{% endraw %}

*“HMAC can be used to determine whether a message sent over an insecure channel has been tampered with, provided that the sender and receiver share a secret key. The sender computes the hash value for the original data and sends both the original data and hash value as a single message. The receiver recalculates the hash value on the received message and checks that the computed HMAC matches the transmitted HMAC.”*

```powershell
Param (
    [uri]
    $Url = "https://dev.azure.com/MY_ORG/_apis/public/distributedtask/webhooks/WebookDemoTrigger/?api-version=6.0-preview",

    [string]
    $Secret = "Demo123!",

    [string]
    $HeaderName = "MyHeader"
)

$Body = @{
    app_name = "my app"
    environment = "prod"
} | ConvertTo-Json

$hmacSha = New-Object System.Security.Cryptography.HMACSHA1 -Property @{
    Key = [Text.Encoding]::ASCII.GetBytes($secret)
}

$hashBytes = $hmacSha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Body))
$signature = ''

$hashBytes | ForEach-Object { $signature += $_.ToString('x2')}

$headers = @{
    $headerName = "sha1=$signature"
}

Invoke-WebRequest -Uri $Url -Body $Body -Method Post -ContentType 'application/json' -Headers $headers
```

**Python**

The below code will import the necessary modules, define a function to generate the sha1 signature and a function to fire the webhook.

```python
# Import modules
import hmac
import hashlib
import json
import requests
import logging

# Configure logging format and level
logging.basicConfig(format='%(asctime)s: %(message)s')
logging.getLogger().setLevel(logging.INFO)

# Data payload for webhook
data = {
    "app_name": "MyLilApp",
    "environment": "Prod",
}

# Generate sha1 signature
def create_sha1_signature(secret, payload):
    
    # Convert payload to json
    data = json.dumps(payload)
    
    # Encode payload and store in bytes format
    data = data.encode("utf-8")
    
    # Encode secret and store in bytes format
    key = secret.encode("utf-8")
    
    # Sign payload using secret and construct sha1 signature
    signature = "sha1=" + hmac.new(key, data, hashlib.sha1).hexdigest()

    return signature

# Trigger webhook with payload
def trigger_azure_webhook():
    
    # Define variables
    secret = "Demo123!"
    header_name = "MyHeader"
    adops_org = "MY_ORG"
    adops_webhook = "WebookDemoTrigger"
    endpoint = f"https://dev.azure.com/{adops_org}/_apis/public/distributedtask/webhooks/{adops_webhook}/?api-version=6.0-preview"
    
    # Construct header
    headers = {
        header_name: create_sha1_signature(secret, data)
    }
    
    # Fire webhook
    try:
        response = requests.post(url=endpoint, json=data, headers=headers)
        response.raise_for_status()
        
        if response.status_code == 200:
            logging.info("The request was a success!")          
        
    except requests.exceptions.HTTPError as errh:
        logging.exception(errh)
        logging.exception(response.text)
    except requests.exceptions.ConnectionError as errc:
        logging.exception(errc)
        logging.exception(response.text)
    except requests.exceptions.Timeout as errt:
        logging.exception(errt)
        logging.exception(response.text)
    except requests.exceptions.RequestException as err:
        logging.exception(err)
        logging.exception(response.text)
        
trigger_azure_webhook()
```

And that’s it! Once fired the pipeline will start and do its job.

Thanks for reading! Feel free to reach out on any of my socials in the bottom.
