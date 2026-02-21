---
title: "Containers under the hood"
description: "A deep dive into how containers actually work on GNU/Linux — from namespaces to cgroups."
draft: false
date: 2026-02-20
tags: [ "linux", "kernel", "docker", "Namespaces", "Cgroups" ]
summary: "A deep dive into how containers actually work on GNU/Linux — from namespaces to cgroups."
---

This article dives into how **containers** actually run on **GNU/Linux**. Not how to use Docker — but what happens underneath when you type `docker run`: how the kernel isolates processes with [namespaces](#what-are-namespaces), controls their resources with [cgroups](#what-are-cgroups), and why understanding this changes the way you troubleshoot, optimize, and secure your systems.

{{< alert >}} 

This article starts from the ground up. If you're already familiar with the basics of containerization, feel free to skip ahead to the Namespaces section.

{{< /alert >}}

## From monoliths to containers

this isn't a strict timeline — it's the evolution of an idea
{{< timeline >}}

{{< timelineItem header="Monolithic app" badge="60' - 2000" icon="cube" >}}
One codebase, one deployment, one server. Everything runs together.
{{< /timelineItem >}}

{{< timelineItem header="Microservices" badge="~2012" icon="list" >}}
The monolith breaks apart. Independent services, independent teams, independent deployments.
{{< /timelineItem >}}

{{< timelineItem header="Virtual machines" badge="~2008 - 2010" icon="server" >}}
Each service gets its own OS. Full isolation, but heavy — minutes to boot, gigabytes of overhead.
{{< /timelineItem >}}

{{< timelineItem header="Containers" badge="~2013" icon="docker" >}}
Same kernel, isolated processes. Milliseconds to start, megabytes of overhead. <strong>Namespaces</strong> + <strong>cgroups</strong> under the hood.
{{< /timelineItem >}}

{{< /timeline >}} 

## The monolithic era 
For decades, applications were built as a single, large unit — a monolith. One codebase, one deployment, one process. Your e-commerce platform? That was one application handling user authentication, product catalog, shopping cart, payment processing, order management, and email notifications. All compiled together, all deployed together, all running in the same process on the same server.
This worked. Until it didn't.
When your product catalog needed more computing power because of a sale event, you couldn't scale just the catalog. You had to scale the entire application — deploy the whole thing on a bigger server or duplicate everything on multiple servers, even though 90% of your code didn't need extra resources. When a developer pushed a bug in the notification system, the entire application went down — including payments. When the team grew from 5 to 50 developers, everyone was working on the same codebase, stepping on each other's toes, and a single deployment could take hours of coordination.
The monolith became a bottleneck for both the infrastructure and the people building it.

## The microservices answer

The idea behind microservices is simple: break the monolith into small, independent services. Each service does one thing, runs as its own process, communicates with others through APIs, and can be deployed independently.
Your e-commerce platform becomes: an auth service, a catalog service, a cart service, a payment service, an order service, a notification service. The catalog team can deploy 10 times a day without touching payments. If the notification service crashes, people can still buy things. Need more capacity for the catalog during Black Friday? Scale just that service, not the whole system.
But microservices created a new problem: instead of one application to deploy and manage, now you have 20. Or 100. Or 500. Each one needs its own environment, its own dependencies, its own runtime. The catalog runs Python 3.11, payments runs Java 17, notifications runs Node.js 20. How do you run all of these on the same servers without them conflicting with each other?

## Virtual machines: the first attempt

The initial answer was virtual machines. Run each service in its own VM with its own operating system. Complete isolation, problem solved.
Except a VM is heavy. Each one runs a full operating system kernel, needs its own allocated RAM even if mostly unused, takes minutes to boot, and consumes disk space for an entire OS image. Running 50 microservices in 50 VMs means 50 copies of Linux eating your resources. You're paying for 50 kernels when all you needed was 50 isolated processes.

## Containers: the lightweight answer

Containers took a different approach. Instead of emulating a full machine with its own kernel, what if you could just make a process think it's alone on the system? Same kernel, shared with the host, but the process sees its own filesystem, its own network, its own process tree, and can only use the resources you allow.
A container starts in milliseconds, not minutes. It uses megabytes, not gigabytes. You can run hundreds on a single machine. And the process inside has no idea it's not running on a dedicated server.
This is where [Docker](https://www.docker.com) came in. Docker didn't invent the underlying technology — Linux namespaces existed since 2002, cgroups since 2008. What Docker did was package it into a tool that made containers accessible. A `Dockerfile` to define your environment, `docker build` to create an image, `docker run` to launch it. Suddenly, any developer could containerize an application in minutes.
But beneath all of this — Docker, Kubernetes, container orchestration — there are just two Linux kernel features doing the real work: **namespaces** for isolation and **cgroups** for resource control. That's what the rest of this article is about.

## Namespaces and Cgroups

### What are namespaces?
**Namespaces** are a Linux kernel feature that gives a process its own isolated view of the system. Instead of seeing everything — all processes, all network interfaces, all mount points — a process inside a namespace only sees what the kernel allows it to see. Nothing is virtualized, nothing is emulated. It's just a **filter** on what already exists.

### Types of namespaces 
#### PID
Every process in Linux has a Process ID. Normally they all share the same numbering — PID 1 is init/systemd, and everything else counts up from there. A PID namespace gives a process its own independent process tree.
The first process inside a new PID namespace becomes PID 1 in that namespace. This is important because PID 1 has a special role in Linux: it adopts orphaned processes and receives signals differently. Inside the namespace, this process is init. But from the outside, it's just a regular process with a normal PID like 58421.
This means a process inside a PID namespace can only see itself and its children. It has no idea that thousands of other processes exist on the host. If it runs `ps aux`, it sees a nearly empty system. If it tries to `kill` a PID outside its namespace, it can't — that PID simply doesn't exist in its world.
 
```bash
# create a new PID namespace
sudo unshare --pid --fork --mount-proc /bin/bash

# inside the namespace
ps aux
# you'll see only bash (PID 1) and ps (PID 2)

echo $$
# output: 1  — you ARE PID 1 in this namespace

# open another terminal and check
ps aux | grep unshare
# you'll see the process with a normal PID like 58421
```

The --mount-proc flag is important: without it, ps reads /proc from the host and you'd still see everything. By remounting /proc, you tell the kernel to show only the processes visible inside this namespace.
Real-world impact: this is why docker top shows different PIDs than what you see inside the container. Same process, two different PID trees.

#### NET
By default, all processes share the same network stack: the same interfaces (`eth0, lo`), the same routing table, the same iptables rules, the same ports. A NET namespace gives a process its own completely independent network stack.
A fresh NET namespace starts with nothing — not even loopback. Just a blank network. You have to set it up: create interfaces, assign IPs, configure routes. This is exactly what Docker does every time you start a container.
The typical pattern is a veth pair — a virtual ethernet cable with two ends. One end goes inside the namespace, one stays outside. Traffic in, traffic out, like a physical cable connecting two machines, except it's all inside the same kernel.

``` bash
# create a named network namespace
sudo ip netns add test_ns

# check: it has nothing
sudo ip netns exec test_ns ip addr
# only the loopback, and it's DOWN

# create a veth pair
sudo ip link add veth0 type veth peer name veth1

# move one end into the namespace
sudo ip link set veth1 netns test_ns

# configure the host side
sudo ip addr add 10.0.0.1/24 dev veth0
sudo ip link set veth0 up

# configure the namespace side
sudo ip netns exec test_ns ip addr add 10.0.0.2/24 dev veth1
sudo ip netns exec test_ns ip link set veth1 up
sudo ip netns exec test_ns ip link set lo up

# test connectivity
sudo ip netns exec test_ns ping 10.0.0.1
# it works — two isolated network stacks talking through a virtual cable

# cleanup
sudo ip netns delete test_ns
```

This is why containers can all bind to port 80 without conflicts — they each have their own NET namespace with their own port space. And this is exactly how Kubernetes networking starts: pods get their own NET namespace, then CNI plugins (Calico, Flannel, Cilium) wire them together.
#### MNT

The MNT namespace isolates mount points. A process in its own MNT namespace can mount and unmount filesystems without affecting the host or other namespaces.
This is the oldest namespace — it was the first one implemented in Linux 2.4.19 — and it's what makes containers see their own root filesystem. When Docker starts a container, it creates a new MNT namespace and mounts the container image as the root filesystem. Inside, the process sees / as its image. Outside, the host filesystem is untouched.

```bash 
# create a new mount namespace
sudo unshare --mount /bin/bash

# mount a tmpfs somewhere — only visible inside this namespace
mount -t tmpfs none /mnt
echo "only I can see this" > /mnt/secret.txt

# from another terminal on the host
cat /mnt/secret.txt
# No such file — the mount doesn't exist in the host namespace
```

Combined with PID namespace: the container sees its own filesystem AND only its own processes. The illusion of a separate machine is getting stronger.

#### UTS
UTS stands for "Unix Time-Sharing" (historical name, don't worry about it). It isolates the hostname and the domain name. That's it.

```bash
sudo unshare --uts /bin/bash
hostname container-01
hostname
# output: container-01

# from the host
hostname
# output: your-original-hostname — unchanged
```

Simple but necessary. Every Docker container has its own hostname (usually the container ID). Without UTS namespace, changing the hostname would affect the entire host.

#### USER

This is the most powerful and the most security-critical one. A USER namespace remaps user and group IDs. A process can be root (UID 0) inside the namespace but mapped to an unprivileged user (say UID 100000) outside.
This is the foundation of rootless containers. The application inside the container thinks it's root and can do root things within its namespace — install packages, bind to port 80, change file ownership. But on the host, it's running as a regular user with no elevated privileges. If the process escapes the container, it's nobody.

```bash 
# create a user namespace (no sudo needed!)
unshare --user --map-root-user /bin/bash

whoami
# output: root

id
# output: uid=0(root) gid=0(root)

# but from the host, this process runs as your regular user
# it CANNOT actually do privileged operations on the host
```

The `--map-root-user` flag maps your `UID` outside to `UID 0` inside. The kernel tracks the mapping in `/proc/<PID>/uid_map` and `/proc/<PID>/gid_map`.
This is why Podman's rootless mode works: it creates a USER namespace where the container process is root inside but your regular user outside. No daemon running as root needed, unlike traditional Docker.

#### IPC

IPC stands for Inter-Process Communication. This namespace isolates shared memory segments, semaphores, and message queues. Processes in different IPC namespaces can't communicate through these mechanisms.
Without this isolation, a process in one container could read shared memory created by a process in another container. Not great for security.
This one is straightforward and rarely something you configure directly. Docker and Kubernetes set it up automatically. You mostly need to know it exists and why: it prevents cross-container data leaks through shared memory.

#### CGROUP 

The cgroup namespace virtualizes the view of /sys/fs/cgroup. A process inside a cgroup namespace sees its own cgroup as the root. It doesn't know it's actually nested under /sys/fs/cgroup/docker/abc123... on the host.
Without it, a process inside a container could read /sys/fs/cgroup and see the entire host's cgroup hierarchy — names of other containers, resource allocations, everything. Not a security risk per se (it's read-only by default) but it's information leakage and it breaks the abstraction.

#### TIME

Added in kernel 5.6 (2020), this is the newest one. It isolates CLOCK_MONOTONIC and CLOCK_BOOTTIME.
The main use case: container migration. If you live-migrate a container from a host that has been running for 200 days to a fresh host with 2 days of uptime, CLOCK_BOOTTIME would suddenly jump backward. The time namespace lets the container keep its own boottime offset, so applications inside don't break.
This doesn't affect wall clock time (CLOCK_REALTIME) — that's still shared with the host.

## Isolation is not enough 

Namespaces give a process its own view of the system. But a view is all they control. Nothing stops a process inside a PID namespace from allocating 64GB of RAM, pinning all CPU cores to 100%, or writing to disk so aggressively that every other process on the host grinds to a halt.
In the hosting provider scenario: you've isolated your 100 customers with namespaces. Customer A can't see customer B's processes anymore. Great. But customer A's runaway script is now consuming all available memory, and the kernel's OOM killer starts terminating customer B's processes to free up resources. Isolation without resource control is only half the solution.

## What are cgroups?

Cgroups (control groups) are a kernel mechanism that limits, accounts, and isolates resource usage of a group of processes. While namespaces answer "what can a process see?", cgroups answer "how much can a process use?"
A cgroup is simply a directory in a virtual filesystem. You create a group, assign resource limits by writing values into files, and then add processes to that group. The kernel enforces the limits. That's it — no daemons, no services, just files and directories.

## Cgroups v1 vs v2

There are two versions and this causes confusion, so let's clear it up.
Cgroups v1 (2008) organized resources into separate hierarchies — one for CPU, one for memory, one for I/O, and so on. Each hierarchy was independent. This created a mess: a process could be in one CPU group but a different memory group, policies conflicted, and the interaction between controllers was unpredictable.

```bash
# v1 layout — separate trees per resource
/sys/fs/cgroup/cpu/
/sys/fs/cgroup/memory/
/sys/fs/cgroup/blkio/
/sys/fs/cgroup/pids/
```

Cgroups v2 (2016, default since kernel 5.8) uses a single unified hierarchy. One tree, all controllers together. A process is in one group and all resource limits apply to that group. Much cleaner, much easier to reason about.

```bash
# v2 layout — single tree, all controllers
/sys/fs/cgroup/
/sys/fs/cgroup/my_group/
/sys/fs/cgroup/my_group/cpu.max
/sys/fs/cgroup/my_group/memory.max
/sys/fs/cgroup/my_group/io.max
```

Today you should be using v2. Docker, Kubernetes, and systemd all support it. To check what your system uses:

```bash
# if this directory structure exists, you're on v2
mount | grep cgroup2

# or check
cat /proc/filesystems | grep cgroup
```

### The resource controllers
Each controller manages one type of resource:

#### Cpu
how much CPU time a group can use. Controlled through `cpu.max`. The format is `$QUOTA $PERIOD` in microseconds. "50000 100000" means: out of every 100ms, this group can use at most 50ms — effectively 50% of one core.

```bash
# limit to 50% of one core
echo "50000 100000" > /sys/fs/cgroup/my_group/cpu.max

# limit to 2 full cores
echo "200000 100000" > /sys/fs/cgroup/my_group/cpu.max

# no limit
echo "max 100000" > /sys/fs/cgroup/my_group/cpu.max
```
#### Memory
hard limit on RAM usage. When a process exceeds it, the kernel's OOM killer is invoked on that group only — it won't touch processes outside the group.

```bash
# limit to 512MB
echo "536870912" > /sys/fs/cgroup/my_group/memory.max

# check current usage
cat /sys/fs/cgroup/my_group/memory.current
```
#### IO 
limits disk read/write bandwidth and IOPS per device. You need the device major:minor number.

```bash
# find your disk's major:minor
lsblk -o NAME,MAJ:MIN
# example: sda  8:0

# limit to 10MB/s write
echo "8:0 wbps=10485760" > /sys/fs/cgroup/my_group/io.max
```
#### PID
limits the number of processes a group can create. Simple but critical: without it, a fork bomb inside a container takes down the entire host.

```bash
# max 100 processes
echo "100" > /sys/fs/cgroup/my_group/pids.max
```

## Hands-on: building a cgroup from scratch

Let's create a cgroup, set limits, and see them enforced:

```bash
# create the group
sudo mkdir /sys/fs/cgroup/demo

# enable controllers (may be needed depending on your system)
cat /sys/fs/cgroup/cgroup.controllers
# output: cpuset cpu io memory hugetlb pids rdma misc

# set a memory limit of 50MB
echo "52428800" | sudo tee /sys/fs/cgroup/demo/memory.max

# set a CPU limit of 20% of one core
echo "20000 100000" | sudo tee /sys/fs/cgroup/demo/cpu.max

# set max 20 processes
echo "20" | sudo tee /sys/fs/cgroup/demo/pids.max

# add your current shell to the group
echo $$ | sudo tee /sys/fs/cgroup/demo/cgroup.procs

# now everything you run from this shell is limited
# test memory limit:
python3 -c "
data = []
while True:
    data.append('A' * 1024 * 1024)  # allocate 1MB chunks
"
# this will get killed when it hits 50MB — OOM inside the cgroup only

# test PID limit:
for i in $(seq 1 25); do sleep 100 & done
# after ~20 you'll see: fork: retry: Resource temporarily unavailable

# check stats
cat /sys/fs/cgroup/demo/memory.current
cat /sys/fs/cgroup/demo/pids.current

# cleanup: move yourself out, then remove the group
echo $$ | sudo tee /sys/fs/cgroup/cgroup.procs
sudo rmdir /sys/fs/cgroup/demo
```

## How docker uses cgroups 

When you run `docker run --memory=512m --cpus=2 nginx`, Docker:
Creates a cgroup (usually under `/sys/fs/cgroup/system.slice/docker-<container_id>.scope/`)
Writes 536870912 to `memory.max`
Writes 200000 100000 to `cpu.max`
Adds the container's main process to cgroup.procs
That's all. No magic. You can verify it yourself:

```bash
# start a limited container
docker run -d --memory=256m --cpus=0.5 --name test nginx

# find its cgroup
CONTAINER_ID=$(docker inspect test --format '{{.Id}}')
cat /sys/fs/cgroup/system.slice/docker-${CONTAINER_ID}.scope/memory.max
# output: 268435456  (256MB in bytes)

cat /sys/fs/cgroup/system.slice/docker-${CONTAINER_ID}.scope/cpu.max
# output: 50000 100000  (50% of one core)

docker rm -f test
```

## Summary:

### Namespaces + Cgroups = Containers
This is the closing section:
A container is not a thing. There is no "container" object in the Linux kernel. What we call a container is a process running with:
- `PID` namespace, so it only sees its own processes
- `NET` namespace, so it has its own network stack
- `MNT` namespace, so it has its own filesystem
- `UTS` namespace, so it has its own hostname
- `USER` namespace, so root inside isn't root outside
- `IPC` and cgroup namespaces to complete the isolation
- `cgroup`, so it can only use the resources you allow   

Run `docker run nginx` and Docker creates all of these in milliseconds. The nginx process doesn't know it's in a container. It thinks it's alone on a machine. But the host kernel knows exactly what's happening and keeps everything under control.
Understanding this changes how you troubleshoot. Container eating too much memory? Check its [cgroup](#what-are-cgroups). Network not working? Inspect the [NET](#NET) namespace. Process can't see a file? Check the [MNT](#MNT) namespace. 
{{< lead >}}
The mystery disappears when you know what's underneath.
{{< /lead >}}

