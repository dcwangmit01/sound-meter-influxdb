# sound-meter-influxdb

## Create a configuration file

config.yaml

```yaml
letsencrypt:
  # A single cert file for all hosts
  certname: certs.domain.com
  email: you@domain.com
  # hosts need to match conf/nginx/sites-enabled/sites.conf.j2
  hosts:
    - mic.domain.com

nginx:
  domain: domain.com
```