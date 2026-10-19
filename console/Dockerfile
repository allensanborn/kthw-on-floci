# The learner's console: the AWS CLI and an SSH client, pointed at floci.
# `aws ec2-instance-connect ssh` opens its tunnel with awscrt, which trusts only
# the OS trust store and always dials port 443. So this container trusts
# floci's CA in its own store and forwards its loopback 443 to floci, where the
# endpoint's DNS name (*.localhost.floci.io -> 127.0.0.1) lands. Your machine's
# trust store is never touched.
FROM public.ecr.aws/aws-cli/aws-cli:2.38.1@sha256:733d5be1015825e4038c6016f3fa9954868ddee1f611b73be795a9cc2e706bfd
RUN dnf install -y -q openssh-clients socat less python3 && dnf clean all
COPY entrypoint.sh /usr/local/bin/kthw-console
RUN chmod 0755 /usr/local/bin/kthw-console
ENTRYPOINT ["/usr/local/bin/kthw-console"]
CMD ["bash", "-l"]
