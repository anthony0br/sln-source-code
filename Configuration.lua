local config = {}

config["Sussex Rail"] = {}
config["Sussex Rail"]["4 car"] = "DMCO-MSOL-PTSOL-DMCO2"
config["Sussex Rail"]["8 car"] = config["Sussex Rail"]["4 car"] .. config["Sussex Rail"]["4 car"]
config["Sussex Rail"]["12 car"] = config["Sussex Rail"]["8 car"] .. config["Sussex Rail"]["4 car"]

return config