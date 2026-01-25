NMB_CONTROL_PLANE = 1
NMB_WORKER = 2
IMAGE= "bento/ubuntu-20.04"


Vagrant.configure("2") do |config|
  # Provider
  config.vm.provider "virtualbox" do |v|
    v.memory = 2048
    v.cpus = 2
  end

  # Control plane
  (1..NMB_CONTROL_PLANE).each do |i|
    config.vm.define "control-plane#{i}" do |control_plane|
      control_plane.vm.box = IMAGE
      control_plane.vm.hostname = "control-plane#{i}"
      control_plane.vm.network "private_network", ip: "192.168.56.#{i+10}"
      control_plane.vm.provision "file", source: "./.ssh/id_rsa.pub", destination: "/tmp/id_rsa.pub"
      control_plane.vm.provision "file", source: "./.ssh/id_rsa", destination: "/tmp/id_rsa"
      control_plane.vm.provision "file", source: "scripts/vagrant/start_k8s.sh", destination: "/tmp/start_k8s.sh"
      control_plane.vm.provision "file", source: "scripts/vagrant/k8s-startup.service", destination: "/tmp/k8s-startup.service"
      control_plane.vm.provision "shell", privileged: true, path: "scripts/vagrant/init_k8s.sh"
      control_plane.vm.provision "shell", privileged: true, path: "scripts/vagrant/init_master.sh"
    end
  end

  # Worker
  (1..NMB_WORKER).each do |i|
    config.vm.define "worker#{i}" do |kubenodes|
      kubenodes.vm.box = IMAGE
      kubenodes.vm.hostname = "worker#{i}"
      kubenodes.vm.network "private_network", ip: "192.168.56.#{i+20}"
      kubenodes.vm.network "forwarded_port", guest: 80, host: 30080, auto_correct: true
      kubenodes.vm.network "forwarded_port", guest: 443, host: 30443, auto_correct: true
      kubenodes.vm.provision "file", source: "./.ssh/id_rsa.pub", destination: "/tmp/id_rsa.pub"
      kubenodes.vm.provision "file", source: "./.ssh/id_rsa", destination: "/tmp/id_rsa"
      kubenodes.vm.provision "file", source: "scripts/vagrant/start_k8s.sh", destination: "/tmp/start_k8s.sh"
      kubenodes.vm.provision "file", source: "scripts/vagrant/k8s-startup.service", destination: "/tmp/k8s-startup.service"
      kubenodes.vm.provision "shell", privileged: true,  path: "scripts/vagrant/init_k8s.sh"
      kubenodes.vm.provision "shell", privileged: true,  path: "scripts/vagrant/init_worker.sh"

      kubenodes.vm.provider "virtualbox" do |pmv|
        pmv.memory = 4096
      end
    end
  end
  
end