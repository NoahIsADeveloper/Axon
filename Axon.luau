--!optimize 2
--!strict

--[[

MIT License

	Copyright (c) 2025 NoahIsADeveloper

	Permission is hereby granted, free of charge, to any person obtaining a copy
	of this software and associated documentation files (the "Software"), to deal
	in the Software without restriction, including without limitation the rights
	to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
	copies of the Software, and to permit persons to whom the Software is
	furnished to do so, subject to the following conditions:

	The above copyright notice and this permission notice shall be included in all
	copies or substantial portions of the Software.

	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
	IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
	FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
	AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
	LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
	OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
	SOFTWARE.

]]

--[[

Written by @NoahIsADeveloper

NOTES
- Listeners are called in the order they are connected in (FIFO)
- Arguments are not cloned
- Please use task.defer when disconnecting connections inside callbacks

[[ SETTINGS ]]
local CONNECTION_POOL_MAX_SIZE = 8

-- // Connection
export type Callback = (self: Connection, ...any) -> ()

local ConnectionPool = table.create(CONNECTION_POOL_MAX_SIZE) :: {Connection}
local Connection = {} :: Connection
Connection.__index = Connection
export type Connection = typeof(setmetatable({} :: {
	__index: Connection,

	_callback: Callback?,
	_connected: boolean,
	_next: Connection?,
	_last: Connection?,
	_async: boolean,

	IsConnected: (self: Connection) -> (boolean),
	Disconnect: (self: Connection) -> (),
}, Connection))

function Connection:IsConnected(): (boolean)
	return self._connected
end

function Connection:Disconnect()
	if not self._connected then error("cannot disconnect Connection that is not connected") end

	self._connected = false
	self._callback = nil

	local last = self._last
	if last then
		last._next = self._next
	end

	self._last = nil
	self._next = nil

	if #ConnectionPool < CONNECTION_POOL_MAX_SIZE then
		table.insert(ConnectionPool, self)
	end
end

local function CreateConnection(callback: Callback, async: boolean?): (Connection)
	local object = (table.remove(ConnectionPool) or setmetatable({}, Connection)) :: any

	object._next = nil
	object._last = nil
	object._async = async or false
	object._callback = callback
	object._connected = true

	return object
end

-- // Axon
local Axon = {} :: Axon
Axon.__index = Axon
export type Axon = typeof(setmetatable({} :: {
	__index: Axon,

	_head: Connection?,
	_tail: Connection?,

	HasConnections: (self: Axon) -> (boolean, number),
	GetConnections: (self: Axon) -> ({Connection}),
	GetConnectionCount: (self: Axon) -> (number),

	Connect: (self: Axon, callback: Callback, async: boolean?) -> (Connection),
	Once: (self: Axon, callback: Callback) -> (Connection),
	Wait: (self: Axon, timeout: number) -> (...any),

	Disconnect: (self: Axon, callback: Callback, allMatching: boolean?) -> (),
	DisconnectAll: (self: Axon) -> (),

	Listen: (self: Axon, signal: RBXScriptSignal) -> (RBXScriptConnection),
	Fire: (self: Axon, ...any) -> (),

	Destroy: (self: Axon) -> (),
}, Axon))

function Axon:HasConnections(): (boolean, number)
	if self._head == nil then return false, 0 end

	local connections = 0
	local connection = self._head

	while connection do
		connections += 1
		connection = connection._next :: any
	end

	return true, connections
end

function Axon:GetConnectionCount(): (number)
	local _, count = self:HasConnections()
	return count
end

function Axon:GetConnections(): ({Connection})
	local connections = {}
	local connection = self._head

	while connection do
		table.insert(connections, connection)
		connection = connection._next
	end

	return connections
end

function Axon:DisconnectAll()
	local connection = self._head

	while connection do
		local next = connection._next
		connection:Disconnect()
		connection = next
	end

	self._head = nil
	self._tail = nil
end

function Axon:Connect(callback: Callback, async: boolean?): (Connection)
	if type(callback) ~= "function" then error(`argument 1 of :Connect(callback: Callback) expected function got {typeof(callback)}`) end

	local connection = CreateConnection(callback, async)
	local tail = self._tail

	if tail then
		connection._last = tail
		tail._next = connection
	else
		self._head = connection
	end

	self._tail = connection
	return connection
end

function Axon:Disconnect(callback: Callback, allMatching: boolean?)
	if type(callback) ~= "function" then error(`argument 1 of :Disconnect(callback: Callback) expected function got {typeof(callback)}`) end
	local connection = self._head

	while connection do
		local next = connection._next

		if connection._callback == callback then
			connection:Disconnect()
			if not allMatching then break end
		end

		connection = next
	end
end

function Axon:Wait(timeout: number): (...any)
	local thread = coroutine.running()

	local connection
	connection = self:Connect(function(_, ...: any)
		connection:Disconnect()
		task.spawn(thread, ...)
	end)

	if timeout then
		task.delay(timeout, function()
			if connection:IsConnected() then
				connection:Disconnect()
				task.spawn(thread)
			end
		end)
	end

	return coroutine.yield()
end

function Axon:Once(callback: Callback): (Connection)
	return self:Connect(function(connection: Connection, ...: any)
		connection:Disconnect()
		callback(connection, ...)
	end)
end

function Axon:Fire(...: any)
	local connection = self._head

	while connection do
		local callback = connection._callback

		if connection._connected and callback then
			local success, errorMessage

			if connection._async then
				success, errorMessage = pcall(task.spawn, callback, connection, ...)
			else
				success, errorMessage = pcall(callback, connection, ...)
			end

			if not success then
				warn(`{debug.traceback(errorMessage)}`)
			end
		end

		connection = connection._next
	end
end

function Axon:Listen(signal: RBXScriptSignal): (RBXScriptConnection)
	if typeof(signal) ~= "RBXScriptSignal" then error(`argument 1 of :Listen(signal: RBXScriptSignal) expected RBXScriptSignal got {typeof(signal)}`) end

	return signal:Connect(function(...)
		self:Fire(...)
	end)
end

function Axon:Destroy()
	self:DisconnectAll()
	setmetatable(self :: any, nil)
	table.clear(self :: any)
end

local function CreateSignal(): (Axon)
	local object = setmetatable({
		_head = nil,
		_tail = nil,
	}, Axon) :: any

	return object
end

return {
	new = CreateSignal,
	wrap = function(signal: RBXScriptSignal): (Axon, RBXScriptConnection)
		if typeof(signal) ~= "RBXScriptSignal" then error(`argument 1 of .wrap(signal: RBXScriptSignal) expected RBXScriptSignal got {typeof(signal)}`) end

		local object = CreateSignal()

		local connection = signal:Connect(function(...)
			object:Fire(...)
		end) :: RBXScriptConnection

        -- Disconnect RBXScriptConnection on Axon:Destroy()
        local oldDestroy = object.Destroy
        function object:Destroy()
            oldDestroy(self)
            connection:Disconnect()
        end

		return object, connection
	end
}