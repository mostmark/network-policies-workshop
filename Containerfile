FROM registry.access.redhat.com/ubi9/ubi:latest

# Install httpd
RUN dnf install -y httpd && \
    dnf clean all && \
    rm -rf /var/cache/dnf

# Remove default Apache welcome page
RUN rm -f /etc/httpd/conf.d/welcome.conf

# Copy static website content
COPY www/ /var/www/html/

# Configure httpd for non-root operation
RUN sed -i 's/Listen 80/Listen 8080/' /etc/httpd/conf/httpd.conf && \
    sed -i 's/#ServerName www.example.com:80/ServerName localhost:8080/' /etc/httpd/conf/httpd.conf && \
    echo "PidFile /tmp/httpd.pid" >> /etc/httpd/conf/httpd.conf

# Redirect logs to stdout/stderr (container best practice)
RUN sed -i 's|ErrorLog "logs/error_log"|ErrorLog /dev/stderr|' /etc/httpd/conf/httpd.conf && \
    sed -i 's|CustomLog "logs/access_log" combined|CustomLog /dev/stdout combined|' /etc/httpd/conf/httpd.conf

# Fix permissions for all directories httpd needs
RUN chgrp -R 0 /var/log/httpd /var/run/httpd /etc/httpd/logs && \
    chmod -R g+rwx /var/log/httpd /var/run/httpd && \
    chown -R apache:0 /var/www/html && \
    chmod -R 755 /var/www/html

USER apache

EXPOSE 8080

CMD ["/usr/sbin/httpd", "-D", "FOREGROUND"]
