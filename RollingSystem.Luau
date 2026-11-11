-- LARP CLUB: all collection, roll and outfit decisions are server-authoritative.
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local DSS=game:GetService("DataStoreService")
local Run=game:GetService("RunService")
local MPS=game:GetService("MarketplaceService")
local root=RS:WaitForChild("Larp")
local catalog=require(root.Catalog)
local byId={} for _,item in ipairs(catalog) do byId[item.id]=item end
local Policy=require(root.RollPolicy)
local FaceOverlay=require(root.FaceOverlay)
local Rules=require(root.CollectionRules)
for _,item in ipairs(require(root.LegacyCatalog)) do
 if not byId[item.id] then item.active=false item.odds=0 byId[item.id]=item table.insert(catalog,item) end
end
local catalogReady=true
local AES=game:GetService("AvatarEditorService")
local allowed={[8]="HatAccessory",[18]="Face",[41]="HairAccessory",[42]="FaceAccessory"}
local detailSlots={Hat="HatAccessory",Face="Face",HairAccessory="HairAccessory",FaceAccessory="FaceAccessory"}
local overrides={}
local function refreshItem(item)
 if item.checkedAt and os.clock()-item.checkedAt<120 then return item.active end
 local ok,d=pcall(function() return AES:GetItemDetailsAsync(item.id,Enum.AvatarItemType.Asset) end)
 local oldValue,oldActive=item.value,item.active
 if ok then
  if d.CreatorTargetId~=1 or d.CreatorType~="User" or not detailSlots[d.AssetType] then
   item.active=false
  else
   local resale=d.HasResellers and (d.LowestResalePrice or 0)>0
   local value=resale and d.LowestResalePrice or d.Price
   item.offSale=d.IsOffSale==true item.saleLocation=d.SaleLocationType
   item.priceKind=resale and "Resale" or (item.offSale and "Reference" or "Listed")
   item.value=type(value)=="number" and value>0 and value or (item.offSale and oldValue or 0)
   item.slot=detailSlots[d.AssetType] item.name=d.Name item.active=(item.value or 0)>0
  end
 else
  local valid,p=pcall(function() return MPS:GetProductInfoAsync(item.id) end)
  if not valid then return false,"Roblox item data is temporarily unavailable." end
  if not p.Creator or p.Creator.Id~=1 or p.Creator.CreatorType~="User" or not allowed[p.AssetTypeId] then
   item.active=false
  else
   item.offSale=not p.IsForSale
   item.value=(p.PriceInRobux and p.PriceInRobux>0) and p.PriceInRobux or (item.offSale and oldValue or 0)
   item.active=(item.value or 0)>0 item.priceKind=item.offSale and "Reference" or "Listed"
  end
 end
 if item.slot=="Face" and item.allowUnpriced and item.value==0 then item.active=true item.priceKind="Unpriced" end
 item.checkedAt=os.clock()
 if item.value~=oldValue or item.active~=oldActive then Policy.Invalidate() overrides[tostring(item.id)]=table.clone(item) end
 return item.active
end
Policy.Odds(catalog)
local rng=Random.new()
local sessions={}
local GROUP_ID=472019064
local GroupService=game:GetService("GroupService")
local Messaging=game:GetService("MessagingService")
local Http=game:GetService("HttpService")
local TOPIC="LarpGlobalPulls_v1"
local seenAnnouncements,announcementOrder={},{}
local function relay(data)
 if type(data)~="table" or type(data.id)~="string" or type(data.value)~="number" or data.value<100000 or type(data.item)~="string" or type(data.user)~="string" then return end
 if seenAnnouncements[data.id] then return end
 seenAnnouncements[data.id]=true table.insert(announcementOrder,data.id)
 if #announcementOrder>500 then seenAnnouncements[table.remove(announcementOrder,1)]=nil end
 root.UpdateEvent:FireAllClients({announcement=data})
end
local function announcePull(p,item)
 if item.value<100000 then return end
 local data={id=Http:GenerateGUID(false),user=p.DisplayName,username=p.Name,item=item.name,assetId=item.id,value=item.value}
 relay(data)
 if Run:IsStudio() or game.GameId==0 then return end
 for attempt=1,3 do
  local ok=pcall(function() Messaging:PublishAsync(TOPIC,data) end)
  if ok then return end task.wait(attempt*2)
 end
 warn("LARP: cross-server announcement unavailable; local announcement delivered.")
end
if not Run:IsStudio() and game.GameId~=0 then task.spawn(function()
 for attempt=1,5 do
  local ok=pcall(function() Messaging:SubscribeAsync(TOPIC,function(message) relay(message.Data) end) end)
  if ok then return end task.wait(attempt*3)
 end
 warn("LARP: global chat subscription unavailable.")
end) end
local function membership(p,s,refresh)
 local now=os.clock()
 if s.memberChecked and now-s.memberChecked<(s.fastMember and 60 or 2) then return s.fastMember end
 local ok,member
 if refresh then
  ok,member=pcall(function()
   for _,group in ipairs(GroupService:GetGroupsAsync(p.UserId)) do if group.Id==GROUP_ID then return true end end
   return false
  end)
 else ok,member=pcall(function() return p:IsInGroupAsync(GROUP_ID) end) end
 s.memberChecked=now
 if ok then s.fastMember=member==true else s.fastMember=false end
 return s.fastMember
end
local function formatValue(value)
 local raw=tostring(math.floor(value or 0))
 local result=raw:reverse():gsub("(%d%d%d)","%1,"):reverse():gsub("^,","")
 return result
end
local function attachOverhead(p,char)
 local head=char:WaitForChild("Head",15) if not head or not char.Parent then return end
 if char:FindFirstChild("LarpOverhead") then return end
 char:SetAttribute("LarpOwnerUserId",p.UserId)
 local humanoid=char:FindFirstChildOfClass("Humanoid")
 if humanoid then humanoid.DisplayDistanceType=Enum.HumanoidDisplayDistanceType.None end
 local tag=Instance.new("BillboardGui") tag.Name="LarpOverhead" tag.Adornee=head
 tag.Size=UDim2.fromOffset(240,56) tag.StudsOffset=Vector3.new(0,2.9,0)
 tag.MaxDistance=90 tag.AlwaysOnTop=false tag.Parent=char
 local name=Instance.new("TextLabel") name.Size=UDim2.fromScale(1,.45) name.BackgroundTransparency=1
 name.Text=p.DisplayName name.TextSize=14 name.Font=Enum.Font.GothamBold name.TextColor3=Color3.new(1,1,1) name.TextStrokeTransparency=.55 name.Parent=tag
 local value=Instance.new("TextLabel") value.Name="Value" value.Position=UDim2.fromScale(0,.45) value.Size=UDim2.fromScale(1,.55)
 value.BackgroundTransparency=1 value.Font=Enum.Font.GothamBlack value.TextSize=16 value.TextStrokeTransparency=.5 value.Parent=tag
 local function update()
  local n=p:GetAttribute("LarpValue") or 0
  value.Text=formatValue(n).." LARP VALUE"
  value.TextColor3=n>=1000000 and Color3.fromRGB(224,151,255) or n>=100000 and Color3.fromRGB(255,205,93) or Color3.fromRGB(183,255,114)
 end
 update()
 local changed=p:GetAttributeChangedSignal("LarpValue"):Connect(update)
 local child=char.ChildAdded:Connect(function(o) if o.Name=="Head" then tag.Adornee=o end end)
 local click=Instance.new("ClickDetector") click.CursorIcon="rbxasset://textures/Cursors/KeyboardMouse/ArrowFarCursor.png" click.Name="ProfileClick" click.MaxActivationDistance=80 click.Parent=char
 click.MouseClick:Connect(function(viewer)
  if viewer==p or not sessions[viewer] then return end
  root.Inspect:FireClient(viewer,p.UserId)
 end)
 char.Destroying:Once(function() changed:Disconnect() child:Disconnect() end)
end

local db
if not Run:IsStudio() and game.GameId~=0 then db=DSS:GetDataStore("LarpClub_v1") end
local sessionToken=game.JobId..":"..game:GetService("HttpService"):GenerateGUID(false)
local function fresh() return {counts={},equipped={},rolls=0,tutorialDone=false,settings=Rules.CleanSettings(nil)} end
local function clean(raw)
 local d=fresh()
 if type(raw)~="table" then return d end
 if type(raw.counts)=="table" then
  for id,n in pairs(raw.counts) do
   if byId[tonumber(id)] and type(n)=="number" and n==n and n>0 then d.counts[tostring(id)]=math.clamp(math.floor(n),1,1000000) end
  end
 end
 d.equipped=Rules.NormalizeEquipped(raw.equipped,d.counts,byId)
 if type(raw.rolls)=="number" and raw.rolls==raw.rolls then d.rolls=math.clamp(math.floor(raw.rolls),0,1000000000) end
 d.settings=Rules.CleanSettings(raw.settings)
 d.tutorialDone=raw.tutorialDone==true
 local pending=raw.pendingReveal
 if type(pending)=="table" and type(pending.token)=="string" and byId[pending.assetId] and d.counts[tostring(pending.assetId)] and type(pending.value)=="number" and pending.value>=10000 then
  d.pendingReveal=pending
 end
 return d
end
local function stats(d)
 local unique,copies=0,0
 for id,n in pairs(d.counts) do if byId[tonumber(id)] then unique+=1 copies+=n end end
 return Rules.WornValue(d,byId),unique,copies
end
local function updateStats(p,s)
 local value,unique=stats(s.data)
 local board=p:FindFirstChild("leaderstats")
 if board then board["LARP Value"].Value=value board.Rolls.Value=s.data.rolls board.Collected.Value=unique end
 p:SetAttribute("LarpValue",value)
end
local function snapshot(p)
 local s=sessions[p] if not s or not s.ready then return nil end
 local value,unique,copies=stats(s.data)
 return {userId=p.UserId,name=p.DisplayName,username=p.Name,counts=s.data.counts,equipped=s.data.equipped,rolls=s.data.rolls,value=value,unique=unique,copies=copies,saveStatus=s.saveStatus,tutorialDone=s.data.tutorialDone,pendingReveal=s.data.pendingReveal,settings=s.data.settings}
end
local function save(p,release)
 local s=sessions[p] if not s or not s.ready or not db or not s.writable or s.saving then return end
 s.saving=true
 local copy=clean(s.data)
 local ok,result=pcall(function()
  return db:UpdateAsync("u"..p.UserId,function(old)
   if type(old)~="table" or old.lock~=sessionToken then return nil end
   return {data=copy,lock=release and "" or sessionToken,expires=release and 0 or os.time()+180}
  end)
 end)
 s.saving=false
 if not ok or not result then
  s.saveStatus="Save interrupted — reconnect before rolling"
  s.writable=false
 else s.saveStatus="Saved" end
end
local function applyOutfit(p)
 local s=sessions[p] local char=p.Character
 if not s or not char or not s.base or s.applying then return false,"Character is still loading." end
 local humanoid=char:FindFirstChildOfClass("Humanoid") if not humanoid or humanoid.Health<=0 then return false,"Respawn to equip." end
 s.applying=true
 local faceTexture
 for _,id in ipairs(s.data.equipped) do
  if byId[id].slot=="Face" then
   local loaded,value=pcall(FaceOverlay.Texture,id)
   if not loaded then s.applying=false return false,"Roblox couldn't load this face texture. Try again." end
   faceTexture=value
  end
 end
 if s.restoreFace then s.restoreFace() s.restoreFace=nil end
 local desc=s.base:Clone()
 -- Preserve the original avatar and append only the game's equipped additions.
 for _,id in ipairs(s.data.equipped) do
  local slot=byId[id].slot
  if slot=="Face" then
   -- Keep base Head and Face IDs; selected classic artwork is applied below.
  else
   local list=desc[slot]
   local found=false
   for existing in string.gmatch(list,"%d+") do if tonumber(existing)==id then found=true break end end
   if not found then desc[slot]=list=="" and tostring(id) or list..","..tostring(id) end
  end
 end
 local ok,err=pcall(function()
  humanoid:ApplyDescriptionResetAsync(desc)
  if faceTexture then
   local head=char:FindFirstChild("Head")
   s.restoreFace=FaceOverlay.Apply(head,faceTexture)
  end
 end)
 desc:Destroy()
 s.applying=false
 if not ok then warn("LARP equip failed:",err) return false,"Roblox couldn't load that item. Try again." end
 return true
end
local function characterReady(p,char)
 local s=sessions[p] if not s then return end
 local humanoid=char:WaitForChild("Humanoid",15)
 local head=char:WaitForChild("Head",15)
 if not humanoid or not head then return end
 if s.restoreFace then s.restoreFace() s.restoreFace=nil end
 if s.base then s.base:Destroy() end
 s.base=humanoid:GetAppliedDescription()
 if next(s.data.equipped) then applyOutfit(p) end
end
local function joined(p)
 if sessions[p] then return end
 local s={data=fresh(),ready=false,writable=true,lastRoll=-10,lastRequest=0,saveStatus=db and "Loading" or "Studio session • not saved"}
 sessions[p]=s
 if db then
  local ok,record=pcall(function()
   return db:UpdateAsync("u"..p.UserId,function(old)
    old=type(old)=="table" and old or {}
    if old.lock and old.lock~="" and old.lock~=sessionToken and (old.expires or 0)>os.time() then return nil end
    return {data=clean(old.data),lock=sessionToken,expires=os.time()+180}
   end)
  end)
  if not ok or not record then
   s.writable=false s.saveStatus="Data unavailable — rejoin to protect your collection"
  else s.data=clean(record.data) s.saveStatus="Saved" end
 end
 s.ready=true
 task.spawn(membership,p,s,false)
 p.CharacterAdded:Connect(function(char) task.spawn(attachOverhead,p,char) end)
 if p.Character then task.spawn(attachOverhead,p,p.Character) end
 local board=Instance.new("Folder") board.Name="leaderstats" board.Parent=p
 for _,name in ipairs({"LARP Value","Rolls","Collected"}) do local n=Instance.new("IntValue") n.Name=name n.Parent=board end
 updateStats(p,s)
 p.CharacterAppearanceLoaded:Connect(function(char) characterReady(p,char) end)
 if p.Character and p:HasAppearanceLoaded() then task.spawn(characterReady,p,p.Character) end
end
Players.PlayerAdded:Connect(joined)
for _,p in ipairs(Players:GetPlayers()) do task.spawn(joined,p) end
Players.PlayerRemoving:Connect(function(p)
 local s=sessions[p] if s then
  while s.saving do task.wait(.1) end
  save(p,true)
  if s.restoreFace then s.restoreFace() end
  if s.base then s.base:Destroy() end
 end
 sessions[p]=nil
end)
local function grantOwned(p,id)
 local s=sessions[p] if not s or not s.ready or not s.writable or not byId[id] then return false end
 local ok,owned=pcall(function() return MPS:PlayerOwnsAssetAsync(p,id) end)
 if not ok or not owned then return false end
 -- Idempotent: verifying ownership never manufactures duplicate collectible copies.
 s.data.counts[tostring(id)]=math.max(1,s.data.counts[tostring(id)] or 0)
 updateStats(p,s)
 root.UpdateEvent:FireClient(p,{profile=snapshot(p),message="Roblox ownership verified. Item added to your collection."})
 task.spawn(save,p,false)
 return true
end
MPS.PromptPurchaseFinished:Connect(function(p,id,purchased)
 local s=sessions[p] if not s or s.pendingPurchase~=id then return end
 s.pendingPurchase=nil
 if not purchased then root.UpdateEvent:FireClient(p,{message="Purchase cancelled."}) return end
 task.spawn(function()
  for attempt=1,5 do
   if not sessions[p] then return end
   if grantOwned(p,id) then return end
   task.wait(attempt)
  end
  if sessions[p] then root.UpdateEvent:FireClient(p,{message="Ownership is still updating. Use Buy / verify again to sync it."}) end
 end)
end)
root.Request.OnServerInvoke=function(p,action,arg)
 local s=sessions[p]
 if not s or not s.ready then return {ok=false,error="Your collection is loading. Try again."} end
 local now=os.clock()
 local allowedActions={Sync=true,Inspect=true,Roll=true,Buy=true,Equip=true,Membership=true,ReviewPull=true,ResolveReveal=true,CompleteTutorial=true,Settings=true}
 if type(action)~="string" or not allowedActions[action] then return {ok=false,error="Unknown request."} end
 s.requests=s.requests or {}
 if now-(s.requests[action] or -100)<.12 then return {ok=false,error="One moment…"} end
 s.requests[action]=now
 if action=="Membership" then return {ok=true,member=membership(p,s,true),groupId=GROUP_ID} end
 if action=="Sync" then
  if not catalogReady then return {ok=false,error="Checking live Roblox prices…"} end
  return {ok=true,profile=snapshot(p),patches=overrides,bands=Policy.Odds(catalog)}
 end
 if action=="Inspect" then
  if type(arg)~="number" then return {ok=false,error="Invalid player."} end
  local target=Players:GetPlayerByUserId(arg)
  if not target then return {ok=false,error="That player left."} end
  return {ok=true,profile=snapshot(target)}
 end
 if not s.writable then return {ok=false,error=s.saveStatus} end
 if action=="Settings" then
  if type(arg)~="table" then return {ok=false,error="Invalid settings."} end
  if arg.key=="soundsEnabled" and type(arg.enabled)=="boolean" then s.data.settings.soundsEnabled=arg.enabled
  elseif arg.key=="autoDelete" and Rules.TierSet[arg.tier] and type(arg.enabled)=="boolean" then s.data.settings.autoDelete[arg.tier]=arg.enabled
  else return {ok=false,error="Invalid setting."} end
  root.UpdateEvent:FireClient(p,{profile=snapshot(p)})
  task.spawn(save,p,false)
  return {ok=true,profile=snapshot(p)}
 end
 if action=="CompleteTutorial" then s.data.tutorialDone=true task.spawn(save,p,false) return {ok=true} end
 if action=="ReviewPull" or action=="ResolveReveal" then
  local receipt=s.data.pendingReveal
  if type(arg)~="table" or not receipt or arg.token~=receipt.token or not s.data.counts[tostring(receipt.assetId)] then return {ok=false,error="No awarded item matches this reveal."} end
  if action=="ReviewPull" then return {ok=true,receipt=receipt} end
  if arg.choice~="Continue" and arg.choice~="Equip" then return {ok=false,error="Choose Continue or Equip."} end
  if s.resolving then return {ok=false,error="Your item is updating."} end
  s.resolving=true
  if arg.choice=="Equip" then
   if s.applying then s.resolving=false return {ok=false,error="Your outfit is updating."} end
   local nextEquipment,reason=Rules.ChangeEquipment(s.data,byId,receipt.assetId,false)
   if not nextEquipment then s.resolving=false return {ok=false,error=reason} end
   local previous=s.data.equipped s.data.equipped=nextEquipment
   local success,err=applyOutfit(p)
   if not success then s.data.equipped=previous s.resolving=false return {ok=false,error=err} end
  end
  if receipt.announceAfterReveal then
   local announced=table.clone(byId[receipt.assetId])
   announced.name=receipt.name announced.value=receipt.value
   task.spawn(announcePull,p,announced)
  end
  s.data.pendingReveal=nil s.resolving=false
  updateStats(p,s)
  root.UpdateEvent:FireClient(p,{profile=snapshot(p)})
  task.spawn(save,p,false)
  return {ok=true,profile=snapshot(p)}
 end
 if action=="Roll" then
  if s.data.pendingReveal then return {ok=false,needsReveal=true,receipt=s.data.pendingReveal,error="Continue or equip your rare pull first."} end
  if not catalogReady then return {ok=false,error="Catalog is loading."} end
  if s.rolling then return {ok=false,error="Your case is already opening."} end
  local fast=type(arg)=="table" and arg.fast==true
  if fast and not membership(p,s,false) then return {ok=false,error="Join the community to unlock fast rolling.",needsGroup=true} end
  local interval=fast and 1.6 or 5.5
  if now-s.lastRoll<interval then return {ok=false,error="Your next roll is almost ready.",retryAfter=interval-(now-s.lastRoll)} end
  s.lastRoll=now
  s.rolling=true
  local item=Policy.Pick(catalog,rng)
  if not item then s.rolling=false return {ok=false,error="No priced collectibles are available right now."} end
  local oldValue=item.value
  local eligible,err=refreshItem(item)
  s.rolling=false
  if not eligible or item.value~=oldValue then
   Policy.Odds(catalog)
   root.UpdateEvent:FireAllClients({itemPatch=item,bands=Policy.Odds(catalog)})
   return {ok=false,error=err or "An item’s price changed. Odds refreshed; open again."}
  end
  local key=tostring(item.id)
  local discarded=Rules.ShouldDelete(s.data.settings,item)
  s.data.rolls+=1
  if not discarded then s.data.counts[key]=(s.data.counts[key] or 0)+1 end
  if not discarded and Rules.HasCutscene(item) then
   s.data.pendingReveal={token=Http:GenerateGUID(false),assetId=item.id,name=item.name,value=item.value,priceKind=item.priceKind,announceAfterReveal=true}
  end
  updateStats(p,s)
  task.spawn(save,p,false)
  if not discarded and not s.data.pendingReveal then task.spawn(announcePull,p,item) end
  root.UpdateEvent:FireClient(p,{profile=snapshot(p)})
  return {ok=true,item=item,receipt=s.data.pendingReveal,autoDeleted=discarded,rarity=Rules.Tier(item.value),duplicate=(s.data.counts[key] or 0)>1,profile=snapshot(p)}
 elseif action=="Buy" then
  if type(arg)~="number" or not byId[arg] then return {ok=false,error="Invalid item."} end
  if s.buyBusy or (s.lastBuy and now-s.lastBuy<3) then return {ok=false,error="Please wait before buying again."} end
  s.lastBuy=now s.buyBusy=true
  local item=byId[arg]
  local eligible=refreshItem(item)
  if not eligible then s.buyBusy=false return {ok=false,error="This item is unpriced or unavailable."} end
  if grantOwned(p,arg) then s.buyBusy=false return {ok=true,profile=snapshot(p),message="You already own this on Roblox. Collection synced."} end
  local ok,details=pcall(function() return AES:GetItemDetailsAsync(arg,Enum.AvatarItemType.Asset) end)
  if not ok or not details.IsPurchasable or (details.IsOffSale==true and not (details.HasResellers and (details.LowestResalePrice or 0)>0)) then s.buyBusy=false return {ok=false,error="This item cannot be purchased right now."} end
  if details.SaleLocationType=="ShopOnly" then s.buyBusy=false return {ok=false,error="Roblox restricts this item to the Marketplace; it cannot be sold inside this game."} end
  if s.pendingPurchase and now-(s.pendingAt or 0)<120 then s.buyBusy=false return {ok=false,error="Close your current Roblox purchase prompt first."} end
  s.pendingPurchase=arg s.pendingAt=now
  local prompted,err=pcall(function() MPS:PromptPurchase(p,arg) end)
  s.buyBusy=false
  if not prompted then s.pendingPurchase=nil return {ok=false,error="Roblox couldn't open this purchase prompt."} end
  return {ok=true,message="Complete or cancel the purchase in Roblox's confirmation window."}
 elseif action=="Equip" then
  if type(arg)~="number" or not byId[arg] or not s.data.counts[tostring(arg)] then return {ok=false,error="Roll this item before equipping it."} end
  if s.applying then return {ok=false,error="Your outfit is updating."} end
  local nextEquipment,reason=Rules.ChangeEquipment(s.data,byId,arg,true)
  if not nextEquipment then return {ok=false,error=reason} end
  local previous=s.data.equipped s.data.equipped=nextEquipment
  local ok,err=applyOutfit(p)
  if not ok then s.data.equipped=previous return {ok=false,error=err} end
  updateStats(p,s)
  task.spawn(save,p,false)
  root.UpdateEvent:FireClient(p,{profile=snapshot(p)})
  return {ok=true,profile=snapshot(p)}
 end
 return {ok=false,error="Unknown request."}
end
task.spawn(function()
 -- Spread metadata refreshes over time; do not block joining on thousands of requests.
 local index=0
 while task.wait(10) do
  index=index%#catalog+1 local item=catalog[index]
  local previousValue,previousActive=item.value,item.active
  local ok=refreshItem(item)
  if previousValue~=item.value or previousActive~=item.active then
   local bands=Policy.Odds(catalog)
   for p,s in pairs(sessions) do
    if s.ready then updateStats(p,s) root.UpdateEvent:FireClient(p,{profile=snapshot(p),itemPatch=item,bands=bands}) end
   end
  end
 end
end)
task.spawn(function() while task.wait(60) do for p in pairs(sessions) do task.spawn(save,p,false) end end end)
game:BindToClose(function()
 local left=0
 for p in pairs(sessions) do left+=1 task.spawn(function()
  local s=sessions[p] while s and s.saving do task.wait(.1) end
  save(p,true) left-=1
 end) end
 local deadline=os.clock()+25 while left>0 and os.clock()<deadline do task.wait(.1) end
end)
print("LARP CLUB server ready • "..#catalog.." verified Roblox items")
