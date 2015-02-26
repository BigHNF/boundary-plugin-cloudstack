# Boundary CloudStack Plugin (pure Lua/Luvit)

Tracks Apache CloudStack general infrastructure metrics (mostly aggregated by zone).

## Prerequisites

- A working (and *configured*) **CloudStack Management Server** running at the configured endpoint (usually `localhost:8080`).
- Metrics are collected via HTTP requests, therefore **all OSes** should work (tested on **Debian-based Linux** distributions).
- Written in pure Lua/Luvit (embedded in `boundary-meter`) therefore **no dependencies** are required.

## Plugin Setup

No special setup is required (except basic configuration of options).

## Configurable Setings
|Setting Name          |Identifier      |Type     |Description                                                                              |
|:---------------------|----------------|---------|:----------------------------------------------------------------------------------------|
|CloudStack Host       |serverHost      |string   |The CloudStack service host for the node (default: 'localhost').                         |
|CloudStack Port       |serverPort      |integer  |The CloudStack service port for the node (default: 8080).                                |
|CloudStack API Key    |apiKey          |string   |The CloudStack Account API Key for signing requests (required).                          |
|CloudStack Secret Key |secretKey       |string   |The CloudStack Account Secret Key for signing requests (required).                       |
|Poll Retry Count      |pollRetryCount  |integer  |The number of times to retry failed HTTP requests (default: 3).                          |
|Poll Retry Delay      |pollRetryDelay  |integer  |The interval (in milliseconds) to wait before retrying a failed request (default: 3000). |
|Poll Interval         |pollInterval    |integer  |How often (in milliseconds) to poll the Couchbase node for metrics (default: 5000).      |

## Collected Metrics

|Metric Name                                |Description                                                |
|:------------------------------------------|:----------------------------------------------------------|
|CLOUDSTACK_MEMORY_TOTAL                    |Total RAM on the source (zone).                            |
|CLOUDSTACK_MEMORY_USED                     |Used RAM on the source (zone).                             |
|CLOUDSTACK_CPU_TOTAL                       |Total CPUs for the source (zone).                          |
|CLOUDSTACK_CPU_USED                        |Used CPUs for the source (zone).                           |
|CLOUDSTACK_STORAGE_TOTAL                   |Total STORAGE for the source (zone).                       |
|CLOUDSTACK_STORAGE_USED                    |Used STORAGE for the source (zone).                        |
|CLOUDSTACK_STORAGE_ALLOCATED_TOTAL         |Total STORAGE ALLOCATED for the source (zone).             |
|CLOUDSTACK_STORAGE_ALLOCATED_USED          |Used STORAGE ALLOCATED for the source (zone).              |
|CLOUDSTACK_VIRTUAL_NETWORK_PUBLIC_IP_TOTAL |Total VIRTUAL NETWORK PUBLIC IPs for the source (zone).    |
|CLOUDSTACK_VIRTUAL_NETWORK_PUBLIC_IP_USED  |Used VIRTUAL NETWORK PUBLIC IPs for the source (zone).     |
|CLOUDSTACK_PRIVATE_IP_TOTAL                |Total PRIVATE IPs for the source (zone).                   |
|CLOUDSTACK_PRIVATE_IP_USED                 |Used PRIVATE IPs for the source (zone).                    |
|CLOUDSTACK_SECONDARY_STORAGE_TOTAL         |Total SECONDARY STORAGE for the source (zone).             |
|CLOUDSTACK_SECONDARY_STORAGE_USED          |Used SECONDARY STORAGE for the source (zone).              |
|CLOUDSTACK_VLAN_TOTAL                      |Total VLAN for the source (zone).                          |
|CLOUDSTACK_VLAN_USED                       |Used VLAN for the source (zone).                           |
|CLOUDSTACK_DIRECT_ATTACHED_PUBLIC_IP_TOTAL |Total DIRECT ATTACHED PUBLIC IPs for the source (zone).    |
|CLOUDSTACK_DIRECT_ATTACHED_PUBLIC_IP_USED  |Used DIRECT ATTACHED PUBLIC IPs for the source (zone).     |
|CLOUDSTACK_LOCAL_STORAGE_TOTAL             |Total LOCAL STORAGE for the source (zone).                 |
|CLOUDSTACK_LOCAL_STORAGE_USED              |Used LOCAL STORAGE for the source (zone).                  |
|CLOUDSTACK_ACTIVE_VIEWER_SESSIONS          |Active viewer sessions per entire infrastructure.          |
|CLOUDSTACK_EVENTS_INFO                     |Count of INFO events per entire infrastructure.            |
|CLOUDSTACK_EVENTS_WARN                     |Count of WARN events per entire infrastructure.            |
|CLOUDSTACK_EVENTS_ERROR                    |Count of ERROR events per entire infrastructure.           |
|CLOUDSTACK_ALERTS                          |Count of ALERTS per entire infrastructure.                 |
|CLOUDSTACK_ALERTS_MEMORY                   |Count of MEMORY-related ALERTS per entire infrastructure.  |
|CLOUDSTACK_ALERTS_CPU                      |Count of CPU-related ALERTS per entire infrastructure.     |
|CLOUDSTACK_ALERTS_STORAGE                  |Count of STORAGE-related ALERTS per entire infrastructure. |
|CLOUDSTACK_ACCOUNTS_TOTAL                  |Total count of ACCOUNTS per entire infrastructure.         |
|CLOUDSTACK_ACCOUNTS_ENABLED                |Total count of ENABLED ACCOUNTS per entire infrastructure. |

## References
[CloudStack REST API Reference](http://cloudstack.apache.org/docs/api/)
