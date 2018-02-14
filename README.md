Ansible With AWS As Infastrurcture
------
The goal of  the project is to build our entire Infastrurcture from scratch, save for a few manually created resources at the outset.It uses anslible role and playbook whcih runs the deployment lifecycle.

Preparing AWS
----
Create an account in Aws
Add a new keypair for SSH access to your instances. You can  create a new private keypair.

Preparing Ansible
------
Insta Boto for AWS communications, if may differ for different platforms.
```pip install python-boto awscli
```
Install Ansible 2.3.x, for Ubuntu you can get that from the Ansible PPA.
```
add-apt-repository ppa:ansible/ansible
apt-get install ansible
```
Add  your AWS access/secret keys into ~/.aws/credentials
````
[Credentials]
aws_access_key_id = <your_access_key_here>
aws_secret_access_key = <your_secret_key_here>
````
Step 1: VPC  creation and  subnet adding for 4 zones.
-----
For creating the vpc and vpc subnet we need to add group variables (means global variables) that are accessable to entire project scope. Define the region ,zone ,the account key pair which used to log into the instance.Add the name of the securtiy group which you need to provide the access to the port connection
````
# group_vars/all/all.yml

region: "us-east-1"
zone: "us-east-1a"
keypair: "key-pair"
security_groups: "game_security_group"
instance_type: "t2.micro"
project_name:  "game"
ami: "ami"
env : "stage"
subnet: ["","","",""]            
volumes:
  - device_name: "/dev/sda1"
    device_type: "gp2"
    volume_size: "8"
    delete_on_termination: "true"
`````
We have add the role for the vpc creation .Add teh tages for subnet  identification .(I  have added the 4 different subnets )
`````
# roles/vp/tasks/main.yml
    - ec2_vpc:
        state: present
        cidr_block: 172.33.0.0/16
        resource_tags: { "Environment":"Development","Name" :"{{project_name}}"}
        subnets:
          - cidr: 172.33.16.0/20
            az: us-east-1a
            resource_tags: { "Environment":"production" ,"Name" :"{{project_name}}"}
          - cidr: 172.33.32.0/20
            az: us-east-1c
            resource_tags: { "Environment":"production","Name" :"{{project_name}}"}
          - cidr: 172.33.64.0/20
            az: us-east-1d
            resource_tags: { "Environment":"production", "Name" :"{{project_name}}"}
          - cidr: 172.33.0.0/20
            az: us-east-1e
            resource_tags: { "Environment":"production","Name" :"{{project_name}}"}
        internet_gateway: True
        route_tables:
          - subnets:
              - 172.33.16.0/20
              - 172.33.32.0/20
              - 172.33.64.0/20
              - 172.33.0.0/20
            routes:
              - dest: 0.0.0.0/0
                gw: igw
        region: us-east-1
      register: vpc
`````

Step 2: Creating securtiy groups for the instances access
------
Providing secuity group with http,https,ssh ascess to the instances so we cah check the instacnes working state and log files by loging into the system.

````
# roles/security/tasks/main.yml

- name: Create security group
  ec2_group:
   name: "{{ project_name }}_security_group"
   description: "{{ project_name }} security group"
   region: "{{ region }}"
   vpc_id: "{{vpc.vpc_id}}"
   rules:
     - proto: tcp  # ssh
       from_port: 22
       to_port: 22
       cidr_ip: 0.0.0.0/0
     - proto: tcp  # http
       from_port: 80
       to_port: 80
       cidr_ip: 0.0.0.0/0
     - proto: tcp  # https
       from_port: 443
       to_port: 443
       cidr_ip: 0.0.0.0/0
   rules_egress:
     - proto: all
       cidr_ip: 0.0.0.0/0
  register: gamefirewall
````

Step 3: Creating lanuch configuraton
------
Now that   I  have already created an AMI image that havs basci applicaton setups such as apache,curl services.

````
# roles/launchconfig/tasks/main.yml

- name:
  ec2_lc:
    name: "{{project_name}}-lc"
    image_id: "{{ami}}"
    key_name: "{{keypair}}"
    vpc_id : "{{vpc.vpc_id}}"
    security_groups: ['default','{{security_groups}}']
    instance_type: "{{instance_type}}"
    user_data: "{{ lookup('file', '../files/userdata.sh') }}"
    region: "{{region}}"
    volumes:
    - device_name: /dev/sda1
      volume_size: 8
      delete_on_termination: true
    assign_public_ip: yes
````
````
# roles/launchconfig/files/userdata.sh
#!/bin/bash
rm /var/www/html/ping.html
echo $PATH > /home/ubuntu/initialPath
export PATH=$PATH:/usr/local/bin
echo $PATH > /home/ubuntu/finalPath
date > /home/ubuntu/startTime
echo "OK" > /var/www/html/ping.html
date > /home/ubuntu/endTime
chown ubuntu:www-data /var/www/html/ping.html
#chown -R ubuntu:www-data /var/www/html/game_name
service ntp stop
ntpd -gq
service ntp start
Step 4: Creating Elastic load balancer
````
````
# roles/laodbalancer/tasks/main.yml


- local_action:
    module: ec2_elb_lb
    name: "{{project_name}}-lb"
    state: present
    region: "{{region}}"
    security_group_names: ['{{security_groups}}']
    cross_az_load_balancing: yes
    subnets: [ '{{vpc.subnets[0].id}}', '{{vpc.subnets[1].id}}', '{{vpc.subnets[2].id}}', '{{vpc.subnets[3].id}}' ]
    listeners:
      - protocol: http
        load_balancer_port: 80
        instance_port: 80
    health_check:
        ping_protocol: http # options are http, https, ssl, tcp
        ping_port: 80
        ping_path: "/ping.html" # not required for tcp or ssl
        response_timeout: 5 # seconds
        interval: 30 # seconds
        unhealthy_threshold: 2
        healthy_threshold: 10
    tags: { "Environment":"production","Name" :"{{project_name}}-lb"}
  delegate_to: localhost
````
Step 5: Create auto scaling group
----
````
# roles/autoscale/tasks/main.yml

- ec2_asg:
    name: "{{project_name}}-asg"
    load_balancers: [ '{{project_name}}-lb' ]
    availability_zones: [ 'us-east-1a', 'us-east-1c','us-east-1d','us-east-1e' ]
    launch_config_name: "{{project_name}}-lc"
    min_size: 1
    max_size: 1
    desired_capacity: 1
    region: "{{region}}"
    vpc_zone_identifier: [ '{{vpc.subnets[0].id}}', '{{vpc.subnets[1].id}}', '{{vpc.subnets[2].id}}', '{{vpc.subnets[3].id}}' ]
    tags:
      - environment: production
      - name: "{{project_name}}-asg"
        propagate_at_launch: no

````

Step 6: Create the playbook
----
````
#establish.yml
- hosts: localhost
  connection: local
  gather_facts: false
  roles:
    - role: vpc
      name: vpc-create
#      register: vpc_result

- hosts: localhost
  connection: local
  gather_facts: no
  tasks:
    - debug: var=vpc.vpc_id
      when: vpc is defined
  roles:
    - role: security
      name: security-group-create
- hosts: localhost
  connection: local
  gather_facts: no
  tasks:
    - debug: var=vpc.vpc_id
      when: vpc is defined
    - debug: var=vpc.subnets[0].id
      when: vpc is defined
  roles:
    -  launchconfig
    -  loadbalancer
    -  autoscale
````



Done!

Now run ansible-playbook establish.yml to  get the desired result.(ansible-playbook establish.yml -vvv to debug the currently running playbook)

You can check the instance attachement on the laodbalancer in aws web console and verfiy the changes.
