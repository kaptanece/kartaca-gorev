{% set os_family = grains['os_family'] %}
{% set fqdn = grains['fqdn'] %}
{% set is_ubuntu = grains['os'] == 'Ubuntu' %}
{% set is_debian = grains['os'] == 'Debian' %}
{% from "kartaca-pillar.sls" import kartaca_password %}

kartaca_user:
  user.present:
    - name: kartaca
    - uid: 2025
    - gid: 2025
    - home: /home/krt
    - shell: /bin/bash
    - password: {{ kartaca_password | yaml_dquote }}

kartaca_group:
  group.present:
    - name: kartaca
    - gid: 2025

kartaca_sudoers:
  file.managed:
    - name: /etc/sudoers.d/kartaca
    - contents: 'kartaca ALL=(ALL) NOPASSWD: /usr/bin/apt\n'
    - mode: 440

timezone_set:
  timezone.system:
    - name: Europe/Istanbul

set_hostname:
  network.system:
    - hostname: kartaca1.local

host_entry:
  host.present:
    - ip: {{ grains['ipv4'][1] }}
    - names:
      - kartaca1.local

ip_forward:
  sysctl.present:
    - name: net.ipv4.ip_forward
    - value: 1
    - config: /etc/sysctl.conf
    - persist: True

install_packages:
  pkg.installed:
    - pkgs:
      - htop
      - tcptraceroute
      - iputils-ping
      - dnsutils
      - sysstat
      - mtr
      - sudo
{% if is_ubuntu %}
      - docker.io
      - docker-compose
{% elif is_debian %}
      - nginx
      - php-fpm
      - php-mysql
      - php-cli
      - php-curl
      - php-gd
      - php-mbstring
      - php-xml
      - php-xmlrpc
      - php-soap
      - php-intl
      - php-zip
      - mariadb-client
{% endif %}

{% if is_ubuntu %}
wordpress_stack:
  docker_container.running:
    - name: wordpress
    - image: wordpress:latest
    - restart_policy: always
    - ports:
      - "8080:80"
    - env:
      WORDPRESS_DB_HOST: "mysql"
      WORDPRESS_DB_USER: "wpuser"
      WORDPRESS_DB_PASSWORD: "wppassword"
      WORDPRESS_DB_NAME: "wordpress"
    - replicas: 3

haproxy_image:
  docker_image.present:
    - name: haproxy:latest
{% endif %}

{% if is_debian %}
nginx_conf:
  file.managed:
    - name: /etc/nginx/nginx.conf
    - source: salt://files/nginx.conf
    - watch_in:
      - service: nginx

nginx_restart:
  service.running:
    - name: nginx
    - enable: True
    - watch:
      - file: /etc/nginx/nginx.conf

wordpress_dl:
  cmd.run:
    - name: wget https://wordpress.org/latest.tar.gz -O /tmp/wordpress.tar.gz
    - creates: /tmp/wordpress.tar.gz

wordpress_unpack:
  archive.extracted:
    - name: /var/www/html
    - source: /tmp/wordpress.tar.gz
    - archive_format: tar
    - if_missing: /var/www/html/index.php

nginx_ssl:
  cmd.run:
    - name: openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/wp.key -out /etc/ssl/certs/wp.crt -subj "/CN=kartaca1.local"
    - creates: /etc/ssl/certs/wp.crt

wp_config_update:
  file.replace:
    - name: /var/www/html/wp-config.php
    - pattern: 'database_name_here'
    - repl: 'wordpress'
    - onlyif: test -f /var/www/html/wp-config.php

logrotate_nginx:
  file.managed:
    - name: /etc/logrotate.d/nginx
    - source: salt://files/logrotate-nginx

nginx_cron_restart:
  cron.present:
    - name: 'Restart nginx monthly'
    - user: root
    - minute: 0
    - hour: 0
    - daymonth: 1
    - cmd: 'systemctl restart nginx'
{% endif %}
