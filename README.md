# ClimaViz.jl

Generate a [web dashboard](https://clima.westus3.cloudapp.azure.com/jsserve/atmos) of your simulation outputs directly from HPC or locally.
Currently supports ClimaAtmos and ClimaLand.

## Instructions:

From HPC, you need to ssh with port forwarding:

```shell
ssh -L 8080:localhost:8080 user@ssh.example.com
```

Install ClimaViz (`Pkg.add(ClimaViz.jl)`) and give the path of your output directory
(e.g., `path = "output/"`). Launch the web app:

```julia
using ClimaViz
dashboard(path)
```

and then open this URL on your local browser:

http://localhost:8080/

<img width="2687" height="1427" alt="image" src="https://github.com/user-attachments/assets/89a5ede3-1ff3-4058-8793-2ad6777738e0" />

## ParamViz.jl

ParamViz.jl is located in dashboard/ParamViz.jl and allows to visualize parameterisations.

![chrome_a0AHoCQMHV](https://github.com/CliMA/ParamViz.jl/assets/22160257/832adffe-5a5b-4d46-9d15-a088bcb4b460)

## CliCal.jl

CliCal.jl is located in dashboard/CliCal.jl and generate a dashboard of calibration eki objects
(from ClimaCalibrate.jl).

![image](https://github.com/user-attachments/assets/156df308-ea98-460b-9044-92e2a00603ab)

## Clouds animations

In animations/clouds, you will find code to generate an animation of clouds from ClimaAtmos outputs.

<p align="center">
  <img src="https://github.com/user-attachments/assets/778b0c14-a5d7-4907-82db-6d1f8a0c5b07" alt="animation (1)">
</p>
