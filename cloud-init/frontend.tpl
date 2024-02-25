#cloud-config
write_files:
- path: /mnt/stateful_partition/haproxy/haproxy.cfg
  permissions: 0644
  owner: root
  content: |
    global
      log stdout format raw daemon debug
    defaults
      log global
      mode http
      option httplog
    frontend example-frontend
      bind *:80
      mode http
      default_backend example-backend
    backend example-backend
      balance roundrobin
      mode http
      server  backend-mig ${be_ip}:80
- path: /etc/systemd/system/haproxy.service
  permissions: 0644
  owner: root
  content: |
    [Unit]
    Description=haproxy container

    [Service]
    ExecStart=/usr/bin/docker run --rm --publish 80:80 -v /mnt/stateful_partition/haproxy/:/usr/local/etc/haproxy/:ro --name=haproxy haproxy:lts-alpine
    ExecStop=/usr/bin/docker stop haproxy
    ExecStopPost=/usr/bin/docker rm haproxy

runcmd:
- systemctl daemon-reload
- systemctl start haproxy.service
