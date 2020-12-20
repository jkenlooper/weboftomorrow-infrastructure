# Web of Tomorrow Infrastructure

Creates infrastructure in AWS for the weboftomorrow static website. Deploys
the following CloudFormation templates.

- `build-change-set.cfn.yaml`
- `security.cfn.yaml`
- `weboftomorrow.cfn.yaml`
- `devops.cfn.yaml`

_It currently depends on another stack that creates many of the root resources._
That root stack is mainly used to setup the shared artifact and static website
buckets as well as many of the roles and other permissions.

![Layout of infrastructure in AWS](/images/weboftomorrow-infrastructure.svg)
## Initial Steps

Create a certificate in the us-east-1 region for www.weboftomorrow.com.

Create the following in parameter store:

- /weboftomorrow/example_public_key
- /weboftomorrow/example_secret_key
- /shared/secret-header-string

Upload the templates to S3. And copy the URL for `build-change-set.cfn.yaml`.
This initial deploy-stack will fail to run the build since the CodeBuild project
doesn't exist yet.

```bash
./deploy-stack.sh
```

Manually create the weboftomorrow-build-change-set stack using
the URL for `build-change-set.cfn.yaml`.

---

**[Change log](CHANGELOG.md)**

[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg?style=flat-square)](http://makeapullrequest.com)
