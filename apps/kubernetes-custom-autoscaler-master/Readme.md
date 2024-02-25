see https://refactorizando.com/en/autoscaling-with-prometheus-and-spring-boot-in-kubernetes/

# Docker Build : 
```
docker build -t autoscaling .
docker run -it autoscaling bash
```
test it : 
```
docker run autoscaling
```

# Github registry

* docker login :
```
docker build -t ghcr.io/castrogne/k8s_vagrant .
docker tag ghcr.io/castrogne/k8s_vagrant ghcr.io/castrogne/k8s_vagrant:latest
docker push ghcr.io/castrogne/k8s_vagrant:latest
```
