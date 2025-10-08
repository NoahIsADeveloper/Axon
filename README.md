# Axon

**A lightweight, fast, and safe Signal library for Roblox written in Luau.**  

---

## Features

- FIFO listener execution (first connected, first called)  
- Supports `Connect`, `Once`, `Wait`, `Disconnect`, and `DisconnectAll`  
- Uses a connection pool to reduce garbage collection overhead  
- Wraps existing `RBXScriptSignal`s  

---

## Usage

### Creating a new signal

```
local Axon = require(path.to.Axon)
local signal = Axon.new()

local conn = signal:Connect(function(self, message)
    print("Received:", message)
end)

signal:Fire("Hello World!")  -- Output: "Received: Hello World!"
```

### Connecting a listener that only fires once

```
signal:Once(function(self, msg)
    print("This only prints once:", msg)
end)

signal:Fire("First call")   -- prints
signal:Fire("Second call")  -- doesn't print
```

### Waiting for a signal

```
local result = signal:Wait(5)  -- waits up to 5 seconds
signal:Fire("Hello Wait!")
print(result)  -- Output: "Hello Wait!"
```

### Disconnecting

```
conn:Disconnect()          -- disconnect a single connection
signal:DisconnectAll()     -- disconnect all connections at once
```

### Wrapping an existing `RBXScriptSignal`

```
local axonSignal, rbxConn = Axon.wrap(workspace.SomeEvent)
axonSignal:Connect(function(_, value)
    print("Wrapped event fired with:", value)
end)
```
