# ansible-role-delete-azure-event-hub
------------

Delete group of resources.  By default use to delete Azure Event Hubs.

<!-- TOC -->
## Table of Contents
------------

- [Requirements](#requirements)
- [Role Variables](#role-variables)
- [Role Defaults](#role-defaults)
- [Example Playbook](#example-playbook)
- [Release Notes](#release-notes)
<!-- /TOC -->

## Requirements
------------

Requires Azure Service Principal Information

## Role Variables
------------

| Parameter | Required | Default | Choices | Comments |
| --- | --- | --- | --- | --- |
| `del_resource_api_version` | Yes | 2017-04-01 | YYYY-MM-DD | Specific API version to be used |
| `del_resource_group` | Yes | None | String value | Resource group |
| `del_resource_provider` | Yes | EventHub | String value | Resource provider type |
| `del_resource_type` | Yes | None | String value | Resource type |
| `del_resource_list` | No | None | Array of objects | List of resources which needed to delete |
| `del_resource_name_key` | No | event_hub_name | String value | Key which return name of resource from resource list  |

## Role Defaults
------------

| Parameter | Required | Default | Choices | Comments |
| --- | --- | --- | --- | --- |
| `azure_event_hub_resourcegroup` | Yes | None | String value | Resource group of resources |
| `azure_event_hub_namespace_name` | Yes | None | String value | The namespace name |

## Example Playbook
------------

``` yaml
---
- hosts: localhost
  connection: local
  vars:
    azure_event_hubs:
      - event_hub_name: "EventHub1"
      - event_hub_name: "EventHub2"
      - event_hub_name: "EventHub3"       
  roles:
    - role: ansible-role-delete-azure-event-hub
      cvx_az:
        subscription: "***"
        resourceGroup: "EventHubGroup"        
      cvx_az_tenant: "***"
      cvx_az_client_id:  "***"
      cvx_az_client_secret:  "***"
      cvx_environment_name: "development"
      cvx_mnemonic: "test"
```

## Release Notes
------------
### v1.0
- Initial v1.0 release