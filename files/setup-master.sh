#!/bin/sh

# Copyright (c) Crossbar.io Technologies GmbH. Licensed under GPL 3.0.

apt-get update
apt-get dist-upgrade -y
apt-get install -y expect binutils awscli
apt-get autoremove -y

PRIVATE_IP=`curl http://169.254.169.254/latest/meta-data/local-ipv4`
INSTANCE_ID=`curl http://169.254.169.254/latest/meta-data/instance-id`

cd /tmp
curl https://download.crossbario.com/crossbarfx/linux-amd64/crossbarfx-latest -o crossbarfx
chmod +x crossbarfx
cp crossbarfx /usr/local/bin/crossbarfx

sudo -u ubuntu CROSSBAR_FABRIC_URL="ws://localhost:${master_port}/ws" /usr/local/bin/crossbarfx shell auth --yes

# https://docs.aws.amazon.com/efs/latest/ug/installing-other-distro.html
git clone https://github.com/aws/efs-utils
cd efs-utils/
./build-deb.sh
apt-get -y install ./build/amazon-efs-utils*deb
cd ..

/usr/bin/docker pull crossbario/crossbarfx:pypy-slim-amd64

# we need RW-access to "/nodes" to drop node activation files in the node directories there
mkdir -p /nodes
echo "${file_system_id} /nodes efs _netdev,tls,accesspoint=${access_point_id_nodes},rw,auto 0 0" >> /etc/fstab
mount -a /nodes

# we (obviously) need RW-access to "/master", since this is the master node directory
mkdir -p /master
echo "${file_system_id} /master efs _netdev,tls,accesspoint=${access_point_id_master},rw,auto 0 0" >> /etc/fstab
mount -a /master

# generate new node key pair
#
mkdir -p /master/.crossbar
crossbarfx keys --cbdir=/master/.crossbar
PUBKEY=`grep "public-key-ed25519:" /master/.crossbar/key.pub  | awk '{print $2}'`
HOSTNAME=`hostname`

# remember vars in environment
#
echo "export CROSSBARFX_PUBKEY="$PUBKEY >> ~/.profile
echo "export CROSSBARFX_HOSTNAME="$HOSTNAME >> ~/.profile
echo "export CROSSBARFX_INSTANCE_ID="$INSTANCE_ID >> ~/.profile

# setup aws credentials mechanism
# https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-role.html
mkdir /home/ubuntu/.aws/
aws_config="$(cat <<EOF
[profile default]
role_arn = arn:aws:iam::${aws_account_id}:role/crossbar-ec2iam-master
credential_source = Ec2InstanceMetadata
EOF
)"
echo "$aws_config" > /home/ubuntu/.aws/config
chown -R ubuntu:ubuntu /home/ubuntu/.aws
chmod 700 /home/ubuntu/.aws

# tag ec2 instance with crossbar node public key
aws ec2 create-tags --region ${aws_region} --resources $INSTANCE_ID --tags Key=pubkey,Value=$PUBKEY
aws ec2 describe-tags --region ${aws_region} --filters "Name=resource-id,Values=$INSTANCE_ID"

# create node configuration
#
node_config="$(cat <<EOF
{
    "version": 2,
    "workers": [
        {
            "transports": [
                "COPY",
                "COPY",
                {
                    "endpoint": {
                        "type": "tcp",
                        "port": ${master_port},
                        "backlog": 1024
                    }
                }
            ]
        },
        "COPY"
    ]
}
EOF
)"
echo "$node_config" > /master/.crossbar/config.json

chown -R ubuntu:ubuntu /master
chmod 700 /master

service_unit="$(cat <<EOF
[Unit]
Description=Crossbar.io FX (Master)
After=syslog.target network.target nss-lookup.target network-online.target docker.service
Requires=network-online.target docker.service

[Service]
Type=simple
User=ubuntu
Group=ubuntu
StandardInput=null
StandardOutput=journal
StandardError=journal
TimeoutStartSec=0
Restart=always
ExecStart=/usr/bin/unbuffer /usr/bin/docker run --rm --name crossbarfx --net=host -t \
    --mount type=bind,source=/var/run/docker.sock,target=/var/run/docker.sock \
    -v /nodes:/nodes:rw \
    -v /master:/master:rw \
    -v /home/ubuntu/.crossbarfx:/master/.crossbarfx:ro \
    -e CROSSBAR_FABRIC_SUPERUSER=/master/.crossbarfx/default.pub \
    -e CROSSBAR_FABRIC_URL=ws://$PRIVATE_IP:${master_port}/ws \
    -e CROSSBARFX_WATCH_TO_PAIR=/nodes \
    crossbario/crossbarfx:pypy-slim-amd64 \
    master start --cbdir=/master/.crossbar
ExecReload=/usr/bin/docker restart crossbarfx
ExecStop=/usr/bin/docker stop crossbarfx
ExecStopPost=-/usr/bin/docker rm -f crossbarfx

[Install]
WantedBy=multi-user.target
EOF
)"
echo "$service_unit" >> /etc/systemd/system/crossbarfx.service

systemctl daemon-reload
systemctl enable crossbarfx.service
systemctl restart crossbarfx.service

aliases="$(cat <<EOF
alias crossbarfx_start='sudo systemctl start crossbarfx'
alias crossbarfx_stop='sudo systemctl stop crossbarfx'
alias crossbarfx_restart='sudo systemctl restart crossbarfx'
alias crossbarfx_status='sudo systemctl status crossbarfx'
alias crossbarfx_logstail='sudo journalctl -f -u crossbarfx'
alias crossbarfx_logs='sudo journalctl -n200 -u crossbarfx'
EOF
)"
echo "$aliases" >> /home/ubuntu/.bashrc
