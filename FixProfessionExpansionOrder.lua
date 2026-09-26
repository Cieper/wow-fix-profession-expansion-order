-- Fix Profession Expansion Order
--
-- Problem:
--   When you search the profession recipe list, matching recipes are grouped by
--   expansion. Blizzard sorts those top-level groups by categoryInfo.uiOrder
--   (see SortRootData in Blizzard_ProfessionsTemplates/Blizzard_Professions.lua).
--   The two newest expansions currently share the same uiOrder (900), so the
--   sort falls through to its tiebreaker: an alphabetical name compare. That
--   puts "Khaz Algar" (K) above "Midnight" (M), even though Midnight is newer.
--
-- Fix:
--   We can't change the uiOrder value that C_TradeSkillUI.GetCategoryInfo hands
--   back, but the ordering itself is done in Lua. We override the root node's
--   sort comparator so that when uiOrder ties, we break the tie by categoryID
--   descending. Content added in a later patch gets a higher category ID, so the
--   newer expansion wins the tie and shows on top. Distinct uiOrder values are
--   left untouched, so every other expansion keeps its existing position.
--
--   The sort must be applied BEFORE the ScrollBox renders the provider. The
--   ScrollBox paints synchronously inside SetDataProvider, so a post-hook (which
--   runs after that paint) leaves the first frame showing Blizzard's order; the
--   re-sort's repaint then only lands on later opens, producing a visible jump
--   or, on the very first open, no change at all. So we wrap SetDataProvider and
--   re-sort the incoming provider before the original runs.
--
--   Both the Recipes tab and the Crafting Orders browse tab use this same list
--   and the same sort, so we patch both.

local function CompareExpansionRoots(a, b)
	local ad, bd = a:GetData(), b:GetData()

	-- Preserve Blizzard's group ordering first (Favorites / Learned /
	-- UnlearnedDivider / Unlearned).
	local ag, bg = ad.group, bd.group
	if ag ~= bg then
		return ag < bg
	end

	local ac, bc = ad.categoryInfo, bd.categoryInfo
	if ac and bc then
		if ac.uiOrder ~= bc.uiOrder then
			return ac.uiOrder < bc.uiOrder
		end
		-- uiOrder tie (e.g. the two newest expansions both sitting at 900):
		-- higher categoryID == more recently added == show it first.
		return ac.categoryID > bc.categoryID
	elseif ac or bc then
		-- Keep real categories ahead of non-category rows, matching Blizzard.
		return ac ~= nil
	end

	return false
end

local function SortProvider(provider)
	if provider and provider.GetRootNode then
		local root = provider:GetRootNode()
		if root then
			-- affectChildren = false: only re-order the top-level expansion groups.
			-- skipSort = false: sort the nodes right now.
			root:SetSortComparator(CompareExpansionRoots, false, false)
		end
	end
end

local function InstallOn(scrollBox)
	if not scrollBox then
		return
	end

	-- Pre-hook: sort the provider before the original SetDataProvider paints it,
	-- so the list renders in our order on the first (and only) paint. A fresh
	-- provider is built on every rebuild, including each search keystroke, so
	-- this runs every time.
	local originalSetDataProvider = scrollBox.SetDataProvider
	scrollBox.SetDataProvider = function(self, provider, retainScrollPosition)
		SortProvider(provider)
		return originalSetDataProvider(self, provider, retainScrollPosition)
	end

	-- If the list is already populated (window open across a /reload), sort the
	-- current provider now so it updates without waiting for the next rebuild.
	SortProvider(scrollBox:GetDataProvider())
end

local installed = false

local function Install()
	if installed then
		return true
	end

	local frame = ProfessionsFrame
	if not frame then
		return false
	end

	-- Recipes tab.
	if frame.CraftingPage and frame.CraftingPage.RecipeList then
		InstallOn(frame.CraftingPage.RecipeList.ScrollBox)
	end

	-- Crafting Orders browse tab (same list, same sort, same bug).
	if frame.OrdersPage and frame.OrdersPage.BrowseFrame and frame.OrdersPage.BrowseFrame.RecipeList then
		InstallOn(frame.OrdersPage.BrowseFrame.RecipeList.ScrollBox)
	end

	installed = true
	return true
end

-- Blizzard_Professions is load on demand, so on a normal login ProfessionsFrame
-- does not exist yet and Install() just reports "not yet".
--
-- This used to be a single EventUtil.ContinueOnAddOnLoaded("Blizzard_Professions")
-- call. That fires its callback exactly once and then forgets you, which stopped
-- being safe in 12.1.0: the TOC now starts with
--
--     Blizzard_Professions_Bootstrap.lua [Bootstrap]
--
-- a partition the client runs at startup, well before the rest of the addon. It
-- defines only ProfessionsFrame_LoadUI and friends. If ADDON_LOADED ever lands
-- for that early partition, a one-shot callback would run while ProfessionsFrame
-- is still nil, bail out, and never get a second chance -- the addon would sit
-- there doing nothing, with no error to show for it. So keep listening until the
-- real files have actually run.
if not Install() then
	local watcher = CreateFrame("Frame")
	watcher:RegisterEvent("ADDON_LOADED")
	watcher:SetScript("OnEvent", function(self, _, addOnName)
		if addOnName == "Blizzard_Professions" and Install() then
			self:UnregisterEvent("ADDON_LOADED")
		end
	end)

	-- Belt and braces. ProfessionsFrame_LoadUI is what actually pulls the addon
	-- in, and it exists from startup on both 12.0.x (where it lived in
	-- UIParent.lua) and 12.1.0 (where it moved into the bootstrap partition), so
	-- this lands right after the load completes however ADDON_LOADED is timed.
	-- Still early enough for our purposes: the wrapper only has to beat the first
	-- SetDataProvider call, which happens when the frame is shown.
	if type(ProfessionsFrame_LoadUI) == "function" then
		hooksecurefunc("ProfessionsFrame_LoadUI", Install)
	end
end

-- Diagnostics -----------------------------------------------------------------
--
-- Whether this addon has anything to do is a question about game DATA, not about
-- Blizzard's Lua. SortRootData only ever reaches its alphabetical tiebreak when
-- two top-level categories report the same uiOrder, and uiOrder comes out of the
-- client, so reading the source tells you nothing.
--
-- C_TradeSkillUI.GetCategories() returns exactly the root categories the recipe
-- list groups a search by, so /fpeo reads them out of the live client and says
-- whether the tie is still there. A profession window has to be open: every
-- C_TradeSkillUI call operates on the currently open trade skill.

local PREFIX = "|cff33ff99Expansion Order|r: "

local function Say(msg)
	DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg)
end

-- Blizzard's comparator, minus the group check (all roots here are real
-- categories in the same group). See SortRootData in Blizzard_Professions.lua.
local function BlizzardLess(a, b)
	if a.uiOrder ~= b.uiOrder then
		return a.uiOrder < b.uiOrder
	end
	local cmp = strcmputf8i or function(l, r) return (l < r and -1) or (l > r and 1) or 0 end
	return cmp(a.name, b.name) < 0
end

-- Ours, matching CompareExpansionRoots above.
local function OursLess(a, b)
	if a.uiOrder ~= b.uiOrder then
		return a.uiOrder < b.uiOrder
	end
	return a.categoryID > b.categoryID
end

local function Names(list)
	local out = {}
	for i, info in ipairs(list) do
		out[i] = info.name
	end
	return table.concat(out, " > ")
end

SLASH_FIXPROFESSIONEXPANSIONORDER1 = "/fpeo"
SLASH_FIXPROFESSIONEXPANSIONORDER2 = "/expansionorder"
SlashCmdList.FIXPROFESSIONEXPANSIONORDER = function()
	if not (C_TradeSkillUI and C_TradeSkillUI.GetCategories and C_TradeSkillUI.GetCategoryInfo) then
		Say("C_TradeSkillUI.GetCategories / GetCategoryInfo are missing on this build.")
		return
	end

	local categories = {}
	for _, categoryID in ipairs({ C_TradeSkillUI.GetCategories() }) do
		local info = C_TradeSkillUI.GetCategoryInfo(categoryID)
		if info and info.name and info.uiOrder and info.categoryID then
			categories[#categories + 1] = info
		end
	end

	if #categories == 0 then
		Say("no categories to read. Open a profession window first, then run this again.")
		return
	end

	-- Report every root category, marking the ones that collide on uiOrder.
	local seen, tied = {}, {}
	for _, info in ipairs(categories) do
		if seen[info.uiOrder] then
			tied[info.uiOrder] = true
		end
		seen[info.uiOrder] = true
	end

	local listing = {}
	for i, info in ipairs(categories) do
		listing[i] = info
	end
	table.sort(listing, OursLess)

	Say(("%d top-level categories:"):format(#listing))
	for _, info in ipairs(listing) do
		Say(("    uiOrder %-5s categoryID %-6s %s%s"):format(
			tostring(info.uiOrder), tostring(info.categoryID), info.name,
			tied[info.uiOrder] and "   <-- uiOrder tie" or ""))
	end

	-- Same list, sorted both ways. If the two agree, the tiebreak never bites.
	local blizzardOrder, ourOrder = {}, {}
	for i, info in ipairs(categories) do
		blizzardOrder[i], ourOrder[i] = info, info
	end
	table.sort(blizzardOrder, BlizzardLess)
	table.sort(ourOrder, OursLess)

	local differs = false
	for i = 1, #ourOrder do
		if ourOrder[i] ~= blizzardOrder[i] then
			differs = true
			break
		end
	end

	if not next(tied) then
		Say("no uiOrder ties, so Blizzard never reaches its alphabetical tiebreak.")
		Say("The bug is fixed in the data and this addon is a harmless no-op. Safe to disable.")
	elseif differs then
		Say("uiOrder tie present AND it changes the order, so this addon is doing real work:")
		Say("    without it: " .. Names(blizzardOrder))
		Say("    with it:    " .. Names(ourOrder))
	else
		Say("uiOrder tie present, but alphabetical order happens to match newest-first here,")
		Say("so nothing visibly changes on this profession. Check another one.")
	end
end
