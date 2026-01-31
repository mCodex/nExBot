CaveBot.Extensions.InWithdraw = {}

-- ClientService helper for cross-client compatibility
local function getClient()
    return ClientService
end

CaveBot.Extensions.InWithdraw.setup = function()
	CaveBot.registerAction("inwithdraw", "#002FFF", function(value, retries)
		local data = string.split(value, ",")
		local withdrawId
		local amount

		-- validation
		if #data ~= 2 then
			warn("CaveBot[InboxWithdraw]: incorrect withdraw value")
			return false
		else
			withdrawId = tonumber(data[1])
			amount = tonumber(data[2])
		end

		local currentAmount = itemAmount(withdrawId)

		if currentAmount >= amount then
			print("CaveBot[InboxWithdraw]: enough items, proceeding")
			return true
		end

		if retries > 400 then
			print("CaveBot[InboxWithdraw]: actions limit reached, proceeding")
			return true
		end

		-- actions
		local inboxContainer = getContainerByName("your inbox")
		delay(100)
		if not inboxContainer then
			if not CaveBot.ReachAndOpenInbox() then
				return "retry"
			end
		end
		local inboxAmount = 0
		if not inboxContainer then
			return "retry"
		end
		for i, item in pairs(inboxContainer:getItems()) do
			if item:getId() == withdrawId then
				inboxAmount = inboxAmount + item:getCount()
			end
		end
		if inboxAmount == 0 then
			warn("CaveBot[InboxWithdraw]: not enough items in inbox container, proceeding")
			local Client = getClient()
			if Client and Client.closeContainer then Client.closeContainer(inboxContainer) elseif g_game then g_game.close(inboxContainer) end
			return true
		end

		local destination
		for i, container in pairs(getContainers()) do
			if container:getCapacity() > #container:getItems() and not string.find(container:getName():lower(), "quiver") and not string.find(container:getName():lower(), "depot") and not string.find(container:getName():lower(), "loot") and not string.find(container:getName():lower(), "inbox") then
				destination = container 
			end
		end

		if not destination then
			print("CaveBot[InboxWithdraw]: couldn't find proper destination container, skipping")
			local Client = getClient()
			if Client and Client.closeContainer then Client.closeContainer(inboxContainer) elseif g_game then g_game.close(inboxContainer) end
			return false
		end

		CaveBot.PingDelay(2)

		local Client = getClient()
		for i, container in pairs(getContainers()) do
			if string.find(container:getName():lower(), "your inbox") then
				for j, item in pairs(container:getItems()) do
					if item:getId() == withdrawId then
						if item:isStackable() then
							if Client and Client.move then Client.move(item, destination:getSlotPosition(destination:getItemsCount()), math.min(item:getCount(), (amount - currentAmount))) elseif g_game then g_game.move(item, destination:getSlotPosition(destination:getItemsCount()), math.min(item:getCount(), (amount - currentAmount))) end
							return "retry"
						else
							if Client and Client.move then Client.move(item, destination:getSlotPosition(destination:getItemsCount()), 1) elseif g_game then g_game.move(item, destination:getSlotPosition(destination:getItemsCount()), 1) end
							return "retry"
						end
						return "retry"
					end
				end
			end
		end
  	end)

 	CaveBot.Editor.registerAction("inwithdraw", "in withdraw", {
 	 value="id,amount",
 	 title="Withdraw Items",
 	 description="insert item id and amount",
 	})
end