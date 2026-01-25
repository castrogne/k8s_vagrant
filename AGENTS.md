# AGENTS.md

This file contains guidelines and commands for agentic coding agents working in this Kubernetes Vagrant project.

## Project Overview

This is a Kubernetes cluster setup project using Vagrant and VirtualBox for local development. The project includes:
- Kubernetes cluster deployment with Vagrant
- Java Spring Boot applications (autoscaler)
- Kubernetes manifests and Helm charts
- Shell scripts for cluster initialization

## Build and Development Commands

### Vagrant Commands
```bash
# Start the cluster
vagrant up

# Start with provisioning
vagrant up --provision

# Stop the cluster
vagrant halt

# Destroy the cluster
vagrant destroy

# SSH into control plane
vagrant ssh control-plane1

# SSH into worker nodes
vagrant ssh worker1
vagrant ssh worker2
```

### Kubernetes Commands
```bash
# Get kubeconfig from control plane
vagrant ssh control-plane1 -c "cat /home/vagrant/.kube/config" > Kubeconfig.yaml

# Set kubeconfig environment
export KUBECONFIG=/path/to/Kubeconfig.yaml

# Check cluster status
kubectl get nodes -o wide

# Apply Calico networking
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.25.0/manifests/calico.yaml
```

### Java Application Commands (apps/kubernetes-custom-autoscaler-master)
```bash
# Build the application
mvn clean install

# Run Spring Boot application
mvn spring-boot:run

# Build Docker image
mvn spring-boot:build-image

# Run tests
mvn test

# Run specific test
mvn test -Dtest=ClassName

# Package application
mvn package
```

### Helm Commands
```bash
# Add repositories
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add jetstack https://charts.jetstack.io
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/

# Update repositories
helm repo update

# Install ingress-nginx
helm -n kube-ingress upgrade --install kube-ingress ingress-nginx/ingress-nginx -f scripts/helm/kube-ingress/ingress-nginx.yml --version 4.7.1

# Install cert-manager
helm -n kube-ingress upgrade --install cert-manager jetstack/cert-manager -f scripts/helm/kube-ingress/cert-manager.yml --version 1.13.1

# Install monitoring stack
helm -n kube-monitoring upgrade --install prometheus prometheus-community/kube-prometheus-stack -f scripts/helm/kube-monitoring/kube-prometheus-stack.yml --version 55.5.1
```

## Code Style Guidelines

### Java Code Style (Spring Boot Applications)
- **Java Version**: Java 11
- **Framework**: Spring Boot 2.4.5
- **Build Tool**: Maven
- **Package Structure**: Follow reverse domain naming (e.g., `com.refactorizando.samples.kubernetes.autoscaler`)
- **Class Naming**: PascalCase for classes, camelCase for methods and variables
- **Dependencies**: Use Lombok for boilerplate reduction, Spring Boot starters
- **Annotations**: Use Spring annotations (@RestController, @Service, @Repository, etc.)
- **Error Handling**: Use Spring's ResponseEntity for HTTP responses
- **Database**: JPA with H2 for development

#### Import Organization
```java
// Java standard libraries first
import java.util.UUID;

// Third-party libraries
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

// Spring framework
import org.springframework.web.bind.annotation.*;

// Local imports last
import com.refactorizando.samples.kubernetes.autoscaler.Car;
```

### YAML/Kubernetes Manifest Style
- **File Extension**: Use `.yml` for Kubernetes manifests
- **Document Separator**: Start with `---` for multi-document files
- **Indentation**: 2 spaces for YAML
- **Naming**: kebab-case for resource names, camelCase for metadata fields
- **Namespace**: Always specify namespace when applicable
- **Labels**: Use consistent app labels for selector matching

#### Example Manifest Structure:
```yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-name
  namespace: namespace-name
spec:
  replicas: 1
  selector:
    matchLabels:
      app: app-name
  template:
    metadata:
      labels:
        app: app-name
      annotations:
        prometheus.io/scrape: "true"
    spec:
      containers:
      - name: container-name
        image: image-name:tag
```

### Shell Script Style
- **Shebang**: Always start with `#!/bin/bash`
- **Variables**: UPPERCASE for constants, lowercase for local variables
- **Functions**: camelCase for function names
- **Error Handling**: Check command exit codes
- **Comments**: Use `#` for comments, provide description for complex operations

### File Organization
```
k8s_vagrant/
├── Vagrantfile                 # Main Vagrant configuration
├── scripts/                    # Shell scripts and configurations
│   ├── init_k8s.sh            # Kubernetes initialization
│   ├── manifest/             # Kubernetes manifests
│   └── helm/                 # Helm chart values
├── apps/                      # Application source code
│   └── kubernetes-custom-autoscaler-master/
└── Kubeconfig.yaml           # Generated kubeconfig file
```

## Testing Guidelines

### Java Application Testing
- **Framework**: JUnit 5 (included with Spring Boot Test)
- **Test Location**: `src/test/java/` following same package structure
- **Test Naming**: `ClassNameTest` for test classes
- **Test Methods**: `shouldDoSomethingWhenCondition()` pattern
- **Mocking**: Use Mockito (included with Spring Boot Test)

### Kubernetes Testing
- **Validation**: Use `kubectl apply --dry-run=client -f manifest.yml`
- **Linting**: Use kubeval or similar tools for YAML validation
- **Integration**: Test deployments in the Vagrant cluster

## Environment Configuration

### Kubernetes Version
- **Default**: 1.26.3 (defined in `scripts/init_k8s.sh`)
- **Variable**: `KUBE_VERSION` can be modified in init script

### Virtual Machine Configuration
- **Control Plane**: 2GB RAM, 2 CPUs
- **Worker Nodes**: 4GB RAM, 2 CPUs
- **Network**: 192.168.56.x private network
- **Image**: bento/ubuntu-20.04

### Application Configuration
- **Database**: H2 in-memory database
- **Metrics**: Prometheus metrics enabled via Spring Actuator
- **Port**: 8080 (default Spring Boot port)

## Common Workflows

### Adding a New Application
1. Create directory under `apps/`
2. Add Spring Boot application with proper package structure
3. Create Dockerfile if needed
4. Add Kubernetes manifests in `scripts/manifest/projets/`
5. Update documentation

### Modifying Cluster Configuration
1. Update `Vagrantfile` for VM changes
2. Modify `scripts/init_k8s.sh` for Kubernetes version changes
3. Test with `vagrant up --provision`

### Adding Helm Charts
1. Add repository to HOWTO.md quick install section
2. Create values file in appropriate `scripts/helm/` subdirectory
3. Update installation commands in documentation

## Security Considerations
- SSH keys are provisioned to VMs (keep `.ssh/` directory secure)
- Kubernetes manifests should use proper RBAC
- Avoid hardcoding sensitive information in manifests
- Use Secrets for sensitive configuration

## Troubleshooting
- Check Vagrant logs for VM provisioning issues
- Use `vagrant ssh` to debug individual nodes
- Verify kubeconfig connectivity with `kubectl get nodes`
- Check pod logs with `kubectl logs -f <pod-name>`