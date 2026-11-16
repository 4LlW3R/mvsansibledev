#!/bin/bash
set -x


path_to_playbook=$BUILD_SOURCESDIRECTORY/custom-deployments/event-hub-creation-recreation/event-hub-creation-recreation.yml


add_event_hub_descriprion() {
    echo \
"""      - event_hub_name: $(echo $EVENTHUBS | jq -r '.['$1'].event_hub_name')
        partition_count: $(echo $EVENTHUBS | jq -r '.['$1'].partition_count')
        message_retention_days: $(echo $EVENTHUBS | jq -r '.['$1'].message_retention_days')""" >> $path_to_playbook

    consumer_groups_count="$(echo $EVENTHUBS | jq -r '.['$1'].consumer_groups | length')"
    if [[ $consumer_groups_count -ne 0 ]]; then
        echo \
"""        consumer_groups:""" >> $path_to_playbook
        for j in $(seq 0 $(($consumer_groups_count-1))); do
            echo \
"""        - name: $(echo $EVENTHUBS | jq -r '.['$1'].consumer_groups | .['$j']')""" >> $path_to_playbook
        done
    fi

    authorization_rules_count="$(echo $EVENTHUBS | jq -r '.['$1'].authorization_rules | length')"
    if [[ $authorization_rules_count -ne 0 ]]; then
        echo \
"""        authorization_rules:""" >> $path_to_playbook
        for k in $(seq 0 $(($authorization_rules_count-1))); do
            echo \
"""        - name: $(echo $EVENTHUBS | jq -r '.['$1'].authorization_rules | .['$k'].name')
          rights:""" >> $path_to_playbook
            rights_count="$(echo $EVENTHUBS | jq -r '.['$1'].authorization_rules | .['$k'].rights | length')"
            for q in $(seq 0 $(($rights_count-1))); do
                echo \
"""          - $(echo $EVENTHUBS | jq -r '.['$1'].authorization_rules | .['$k'].rights | .['$q']')""" >> $path_to_playbook
            done
        done
    fi
}



echo \
"""---
- hosts: localhost
  connection: local

  vars:""" > $path_to_playbook

if [[ -n "$RESOURCE_GROUP" ]]; then
    echo \
"""    azure_event_hub_resourcegroup: $RESOURCE_GROUP""" >> $path_to_playbook
fi
if [[ -n "$NAMESPACE_NAME" ]]; then
    echo \
"""    azure_event_hub_namespace_name: $NAMESPACE_NAME""" >> $path_to_playbook
fi
if [[ -n "$LOCATION" ]]; then
    echo \
"""    azure_event_hub_location: $LOCATION""" >> $path_to_playbook
fi
if [[ -n "$SKU_NAME" ]]; then
    echo \
"""    azure_event_hub_sku_name: $SKU_NAME""" >> $path_to_playbook
fi
if [[ -n "$SKU_CAPACITY" ]]; then
    echo \
"""    azure_event_hub_sku_capacity: $SKU_CAPACITY""" >> $path_to_playbook
fi


echo \
"""    azure_event_hubs:""" >> $path_to_playbook


eventhubs_count="$(echo $EVENTHUBS | jq -r '. | length')"
for i in $(seq 0 $(($eventhubs_count-1))); do
    add_event_hub_descriprion $i
done


echo \
"""
  roles:""" >> $path_to_playbook

if [[ $MODE != "create" ]]; then
    echo \
"""    - role: ansible-role-delete-azure-event-hub""" >> $path_to_playbook
fi

echo \
"""    - role: ansible-role-azure-event-hub""" >> $path_to_playbook



cat $path_to_playbook