local Dodger= {}

Dodger.optionEnable = Menu.AddOption({ "Utility","Smart Dodge"}, "Enabled", "Auto Dodger")

Dodger.font = Renderer.LoadFont("Tahoma", 50, Enum.FontWeight.EXTRABOLD)

Dodger.animationSkillMap = {
    --zeus_cast4_thundergods_wrath="zuus_thundergods_wrath",
}
Dodger.animationDirty = {}
Dodger.dodgeQueue={}
Dodger.heroMap={}
Dodger.tick = 0
Dodger.projectileQueue={}
Dodger.defendSkillsQueue={}

function Dodger.OnUpdate()
    if not Menu.IsEnabled(Dodger.optionEnable) then return end
    local myHero = Heroes.GetLocal()
    if not myHero then return end 
    
    Dodger.init()
    if #Dodger.dodgeQueue >0 then
        --Log.Write("count:   "..#Dodger.dodgeQueue)
    end

    Dodger.castAnimDodger()
    Dodger.castProjectileDodger()
    Dodger.OnUnitAbility()
    
end

function Dodger.OnGameStart()
	Dodger.animationDirty = {}
	Dodger.dodgeQueue={}
	Dodger.heroMap={}
	Dodger.heroMapDirty=false
	Dodger.projectileQueue={}
	Dodger.defendSkillsQueue={}
	Dodger.initSkillInfoMap()
end

function Dodger.OnScriptLoad()
	Dodger.initSkillInfoMap()
end
function Dodger.init()
    local myHero = Heroes.GetLocal()
    local myName = NPC.GetUnitName(myHero)
    if Dodger.tick > GameRules.GetGameTime() then return end
    Dodger.heroMap={}
    Dodger.tick = GameRules.GetGameTime()+1
    Dodger.skillProjectileMap = Dodger.table_invert(Dodger.projectileSkillMap)

    for i = 1,Heroes.Count() do
        local hero = Heroes.Get(i)
        if Entity.IsAlive(hero) and not Entity.IsSameTeam(myHero, hero) and not NPC.IsIllusion(hero) then
            local hero = Heroes.Get(i)
            local heroName = NPC.GetUnitName(hero)
            
            for j = 0,5 do
                local ability = NPC.GetAbilityByIndex(hero, j)
                local abilityName = Ability.GetName(ability)
                
                if Dodger.skillInfoMap[abilityName] or Dodger.skillProjectileMap[abilityName] then
                	Log.Write("heroMap:     "..heroName)
                    Dodger.heroMap[heroName] = hero
                end
            end
        end
        --Log.Write("total heroes:"..i)
    end
    for i =0,5 do
    	local myAbility = NPC.GetAbilityByIndex(myHero,i)
    	local name = Ability.GetName(myAbility)
    	if Dodger.defendSkills[name] then
    		Dodger.defendSkillsQueue[name] = myAbility
    	end
    end
end

function Dodger.OnUnitAbility()
    for skillName,items in pairs(Dodger.skillInfoMap) do
        for heroName,hero in pairs(Dodger.heroMap) do
        	if NPCs.Contains(hero) then
	            local skill = NPC.GetAbility(hero,skillName)
	            if skill and Ability.IsInAbilityPhase(skill) then
	                local haveSkill = false
	                for i = 1, #Dodger.dodgeQueue do
	                    local content = Dodger.dodgeQueue[i]
	                    local abilityName = content['abilityName']
	                    --Log.Write(abilityName..":"..skillName)
	                    if abilityName == skillName then
	                        haveSkill = true
	                    end
	                end 

	                if not haveSkill then
	                    table.insert(Dodger.dodgeQueue,{abilityName = skillName, entity=hero,time=GameRules.GetGameTime() + Ability.GetCastPoint(skill)})
	                end
	            end
	        end
        end
    end
end

function Dodger.tablelength(T)
  local count = 0
  for _ in pairs(T) do count = count + 1 end
  return count
end

function Dodger.castAnimDodger()

    local myHero = Heroes.GetLocal()
    if not myHero then return end 
    for i = 1,#Dodger.dodgeQueue do
        local content = Dodger.dodgeQueue[i]
        local hero = content['entity']
        local abilityName = content['abilityName']
        local effectiveTime = content["time"]
        local ability = NPC.GetAbility(hero,abilityName)

        local isTargetMe = Dodger.isTargetMe(myHero,hero, ability)

        if Dodger.skillInfoMap[abilityName]['isGlobal'] or isTargetMe or Dodger.skillInfoMap[abilityName]['afterEffect'] and Dodger.skillInfoMap[abilityName]['wasTargetMe'] then     
            local items = Dodger.skillInfoMap[abilityName]['item']
            --Log.Write("effectiveTime:"..(effectiveTime-0.1).."  time:"..GameRules.GetGameTime())
            if isTargetMe and Dodger.skillInfoMap[abilityName]['afterEffect'] then
            	Dodger.skillInfoMap[abilityName]['wasTargetMe'] = true
            end
            for x,y in pairs(items) do
                local itemName = x
                local abilityType = y['abilityType']
                local time = y['time']
                if GameRules.GetGameTime()>=effectiveTime-time-NetChannel.GetAvgLatency(Enum.Flow.FLOW_OUTGOING) then
                   Dodger.useItems(myHero,itemName,abilityName,abilityType,hero)
                end
            end
        end

        if Dodger.skillInfoMap[abilityName]['used'] then
        	Dodger.skillInfoMap[abilityName]['wasTargetMe'] = false   
        elseif ability and not Ability.IsInAbilityPhase(ability) and not Entity.IsDormant(hero) and not Dodger.skillInfoMap[abilityName]['afterEffect'] then
        	Dodger.skillInfoMap[abilityName]['wasTargetMe'] = false
            table.remove(Dodger.dodgeQueue,i)
        elseif ability and not Entity.IsDormant(hero) and Dodger.skillInfoMap[abilityName]['afterEffect'] then
        	if Ability.GetCooldownTimeLeft(ability) == 0 and not Ability.IsInAbilityPhase(ability) or GameRules.GetGameTime()>effectiveTime+1 then
        		Dodger.skillInfoMap[abilityName]['wasTargetMe'] = false
        		table.remove(Dodger.dodgeQueue,i)
        	end
        end
        if  GameRules.GetGameTime()>effectiveTime+1 then
        	Dodger.skillInfoMap[abilityName]['wasTargetMe'] = false
        	Dodger.skillInfoMap[abilityName]['used'] = false
        	table.remove(Dodger.dodgeQueue,i)
        end
    end
end

function Dodger.castProjectileDodger()
	for i= 1, #Dodger.projectileQueue do
		local content = Dodger.projectileQueue[i]
		local projectile=content.projectile
		local source = content.source
		local sourceLocation = content.sourceLocation
		local target = content.target
		local moveSpeed = content.moveSpeed
		local name = content.name
		local time = content.time
		local myHero = Heroes.GetLocal()

		if target == myHero then
			local myPos = Entity.GetAbsOrigin(myHero)
			local abilityName = Dodger.projectileSkillMap[name]
			local items = Dodger.skillInfoMap[abilityName]['projectileItem']
			for x,y in pairs(items) do
				local itemName = x
                local abilityType = y['abilityType']
                local range = y['range']
                local dist = (sourceLocation - myPos):Length2D()
				local travelTime = (dist-range)/moveSpeed
				--Log.Write("time:"..(time+travelTime).."	cur:"..GameRules.GetGameTime())
				if GameRules.GetGameTime() > travelTime + time - NetChannel.GetAvgLatency(Enum.Flow.FLOW_OUTGOING) then
					Dodger.useItems(myHero,itemName,abilityName,abilityType,source)
				end
			end
			if Dodger.skillInfoMap[abilityName]['used'] or not projectile or GameRules.GetGameTime() > time + 1 then
				table.remove(Dodger.projectileQueue,i)
				Dodger.skillInfoMap[abilityName]['used'] = false
			end
		end
	end
end

function Dodger.useItems(myHero,itemName,abilityName,abilityType,enemy)
	if not NPC.IsStunned(myHero) then
        local item = NPC.GetItem(myHero,itemName)
        local mana = NPC.GetMana(myHero)
        if not Dodger.skillInfoMap[abilityName]['used'] and abilityType == 1 and item and Ability.IsReady(item) and Ability.IsCastable(item, mana) then
            Log.Write(Ability.GetName(item).. "is used")
            if Dodger.skillInfoMap[abilityName]['castOnEnemy'] and NPC.IsEntityInRange(myHero, enemy, Dodger.skillInfoMap[abilityName]['defendRange'] + NPC.GetCastRangeBonus(enemy))then
            	Ability.CastTarget(item,enemy)
            else 
            	Ability.CastTarget(item,myHero)
            end
            Dodger.skillInfoMap[abilityName]['used'] = true
            Dodger.skillInfoMap[abilityName]['wasTargetMe'] = false
        elseif not Dodger.skillInfoMap[abilityName]['used'] and abilityType == 0 and item and Ability.IsReady(item) and Ability.IsCastable(item, mana) then
            Log.Write(Ability.GetName(item).. "is used")    
            Ability.CastNoTarget(item)
            Dodger.skillInfoMap[abilityName]['used'] = true
            Dodger.skillInfoMap[abilityName]['wasTargetMe'] = false
        end
    end
end

function Dodger.doubleClickItem(myHero, itemName)
	local item = NPC.GetItem(myHero, itemName, true)
	if not item then return end
	for i = 0, 5 do
		local slotItem = NPC.GetItemByIndex(myHero, i)
		if slotItem and Ability.GetName(slotItem)==itemName then
			if Ability.IsReady(slotItem) then
				Engine.ExecuteCommand("dota_item_execute "..i)
				Engine.ExecuteCommand("dota_item_execute "..i)
				return
			end
		end
	end
end


function Dodger.isTargetMe(myHero,enemy, ability)
    if NPC.IsDormant(enemy) then return false end

    local angle = Entity.GetRotation(enemy)
    local angleOffset = Angle(0, 45, 0)
    angle:SetYaw(angle:GetYaw() + angleOffset:GetYaw())
    local x,y,z = angle:GetVectors()
    local direction = x + y + z
    local name = NPC.GetUnitName(enemy)
    direction:SetZ(0)


    local abilityName = Ability.GetName(ability)
    local abilityLevel = Ability.GetLevel(ability)
    Log.Write(abilityName)
    if Dodger.skillInfoMap[abilityName]["isGlobal"] then return true end

    local range = Dodger.skillInfoMap[abilityName]["range"][abilityLevel]
    local radius = Dodger.skillInfoMap[abilityName]["radius"][abilityLevel]
    local origin = NPC.GetAbsOrigin(enemy)
    local dest = NPC.GetAbsOrigin(myHero)
    local dist = origin-dest
    dist = dist:Length2D()

    local bonusRange = NPC.GetCastRangeBonus(enemy)
    range = range+bonusRange
    --Log.Write("range:"..range.." radius:"..radius.." dist:"..dist)

    if abilityName == "faceless_void_chronosphere" and NPC.GetAbility(enemy, "special_bonus_unique_faceless_void_4") then
        radius = radius +175
    end 

    local pointsNum = math.floor(range/5) + 1
    for i = pointsNum,1,-1 do 
        direction:Normalize()
        --Log.Write(5*(i-1))
        direction:Scale(5*(i-1))
        --Log.Write(direction:Length2D())
        local pos = direction + origin
        -- local x, y, onScreen = Renderer.WorldToScreen(pos)
        -- Renderer.DrawTextCentered(Dodger.font, x , y,"x", 1)

        if NPC.IsPositionInRange(myHero, pos, radius, 0) then 
            return true 
        end
    end 
    return false
end
function Dodger.OnUnitAnimation(animation)
    if NPC.IsHero(animation.unit) then
        --Log.Write("OnAnimation      name:"..animation.sequenceName.."      unit:"..NPC.GetUnitName(animation.unit).."      sequenceVariant:"..animation.sequenceVariant.."     playbackRate:"..animation.playbackRate.."      castpoint:"..animation.castpoint.."      type:"..animation.type.."    activity:"..animation.activity)
        --Log.Write(Ability.GetName(NPC.GetAbilityByIndex(animation.unit,5))..",      "..Ability.GetCastPoint(NPC.GetAbilityByIndex(animation.unit,5)))
        
        Dodger.initAnimationSkillMap(animation)
        local skillName = Dodger.animationSkillMap[animation.sequenceName]
        if skillName and not Entity.IsSameTeam(animation.unit, Heroes.GetLocal()) then
            table.insert(Dodger.dodgeQueue,{abilityName = skillName, entity=animation.unit,time=GameRules.GetGameTime() + animation.castpoint})
        end
    end
end
-- function Dodger.OnParticleCreate(particle)
--     Log.Write("particle:"..particle.name.." index:"..particle.index)
--     --  if particle.name =="disruptor_glimpse_targetend" then
--     --  	Dodger.particleIndexNameMap[particle.index] = particle.name
--     --  end
-- end

-- function Dodger.OnParticleUpdate(particle)
	
-- 	-- if particle.position and particle.index ~= 3 and Dodger.particleIndexNameMap[particle.index] =="disruptor_glimpse_targetend" then
-- 	--Log.Write(particle.index)
-- 	-- 	local x, y, vis = Renderer.WorldToScreen(particle.position)
--  --    	Renderer.DrawTextCentered(Dodger.font, x, y, "Here", 1)
-- 	-- end
-- end

-- function Dodger.OnEntityCreate(ent)
-- 	--Log.Write(Entity.GetAbsOrigin(ent):__tostring())
-- end

function Dodger.OnProjectile(projectile)
	--Log.Write(projectile.name)
	if Dodger.projectileSkillMap[projectile.name] and Entity.IsSameTeam(Heroes.GetLocal(),projectile.target) then
		table.insert(Dodger.projectileQueue, {
			projectile=projectile,
			source = projectile.source,
			sourceLocation = Entity.GetAbsOrigin(projectile.source),
			target = projectile.target,
			moveSpeed = projectile.moveSpeed,
			name = projectile.name,
			time = GameRules.GetGameTime()
		})
	end
end

-- function Dodger.OnLinearProjectileCreate(projectile)
-- 	Log.Write(projectile.name)
-- end


function Dodger.initAnimationSkillMap(animation)
    if Dodger.animationHeroMapData[animation.sequenceName] and not Dodger.animationDirty[animation.sequenceName] then
        local content = Dodger.animationHeroMapData[animation.sequenceName]

        local heroName = content[1]
        local slot = content[2]
        --Log.Write("name:"..heroName.."  slot:"..slot)
        if not Dodger.heroMap[heroName] then return end
        local ability = NPC.GetAbilityByIndex(Dodger.heroMap[heroName],slot)
        if Dodger.heroMap[heroName] and Dodger.skillInfoMap[Ability.GetName(ability)] then
            Dodger.animationSkillMap[animation.sequenceName] = Ability.GetName(ability)
            Log.Write("we got on mapping from animation to ability: "..animation.sequenceName.."/"..Ability.GetName(ability))
        end
        Dodger.animationDirty[animation.sequenceName] = true
    end
end

function Dodger.table_invert(t)
   local s={}
   for k,v in pairs(t) do
     s[v]=k
   end
   return s
end

function Dodger.initSkillInfoMap()
	Dodger.skillInfoMap ={}
	Dodger.skillInfoMap['zuus_thundergods_wrath'] = 
	{
	    item={
	            item_pipe={abilityType=0, time=0.3},
	            item_hood_of_defiance={abilityType=0, time=0.3},
	            item_cyclone={abilityType=1, time=0.2}, 
	            item_manta={abilityType=0,time=0.05}
	        },
	    isGlobal= true,
	    radius= nil
	}
	Dodger.skillInfoMap['magnataur_reverse_polarity'] = 
	{
	    item={
	            item_cyclone={abilityType=1, time=0.2}, 
	            item_manta={abilityType=0,time=0.05},
	            item_pipe={abilityType=0, time=0.3},
	            item_hood_of_defiance={abilityType=0, time=0.3}
	        },
	    isGlobal= false,
	    radius = {410,410,410},
	    range = {0,0,0}
	}
	Dodger.skillInfoMap['faceless_void_chronosphere'] = 
	{
	    item={  
	            item_ghost={abilityType=0, time=0.1},
	            item_manta={abilityType=0,time=0.08},
	            item_cyclone={abilityType=1, time=0.12}, 
	            item_pipe={abilityType=0, time=0.1},
	            item_hood_of_defiance={abilityType=0, time=0.1}
	        },
	    isGlobal= false,
	    radius={425,425,425},
	    range={600,600,600}
	}
	Dodger.skillInfoMap['lina_laguna_blade'] = 
	{
	    item={  
	            item_manta={abilityType=0,time=-0.2},
	            item_lotus_orb={abilityType=1, time=0.15},
	            item_blade_mail={abilityType=0, time=0.1}, 
	            item_cyclone={abilityType=1, time=0}, 
	            item_pipe={abilityType=0, time=0},
	            item_hood_of_defiance={abilityType=0, time=0}
	        },
	    isGlobal= false,
	    radius={50,50,50},
	    range={600,600,600},
	    afterEffect = true,
	    wasTargetMe = false
	}

	Dodger.skillInfoMap['lion_finger_of_death'] = 
	{
	    item={  
	            item_manta={abilityType=0,time=-0.2},
	            item_lotus_orb={abilityType=1, time=0.15},
	            item_blade_mail={abilityType=0, time=0.1}, 
	            item_cyclone={abilityType=1, time=0}, 
	            item_pipe={abilityType=0, time=0},
	            item_hood_of_defiance={abilityType=0, time=0}
	        },
	    isGlobal= false,
	    radius={50,50,50},
	    range={900,900,900},
	    afterEffect = true,
	    wasTargetMe = false
	}
	Dodger.skillInfoMap['terrorblade_sunder'] = 
	{
	    item={  
	            item_lotus_orb={abilityType=1, time=0.15},
	        },
	    isGlobal= false,
	    radius={50,50,50},
	    range={475,475,475}
	}

	Dodger.skillInfoMap['slardar_slithereen_crush'] = 
	{
	    item={  
	            item_manta={abilityType=0,time=0.1},
	            item_cyclone={abilityType=1, time=0.2}
	        },
	    isGlobal= false,
	    radius={350,350,350,350},
	    range={0,0,0,0}
	}

	Dodger.skillInfoMap['axe_berserkers_call'] = 
	{
	    item={  
	            item_manta={abilityType=0,time=0.13},
	            item_cyclone={abilityType=1, time=0.2}
	        },
	    isGlobal= false,
	    radius={300,300,300,300},
	    range={0,0,0,0}
	}
	Dodger.skillInfoMap['huskar_life_break'] = 
	{
	    item={  
	    		item_cyclone={abilityType=1, time=0}, 
	    		item_pipe={abilityType=0, time=0},
	            item_hood_of_defiance={abilityType=0, time=0},
	    		item_blade_mail={abilityType=0, time=0}
	            -- item_lotus_orb={abilityType=1, time=0}
	        },
	    isGlobal= false,
	     afterEffect = true,
	    radius={10,10,10},
	    range={550,550,550}
	}

	Dodger.skillInfoMap['pangolier_gyroshell'] = 
	{
	    item={  
	    		item_force_staff={abilityType=1, time=0.18}, 
	        },
	    isGlobal= true,
	    castOnEnemy = true,
	    defendRange = 750,
	    radius={50,50,50},
	    range={550,550,550}
	}

	Dodger.skillInfoMap['doom_bringer_doom'] = 
	{
	    item={  
	            item_lotus_orb={abilityType=1, time=0.15},
	            item_blade_mail={abilityType=0, time=0.1}, 
	            item_manta={abilityType=0,time=0.1},
	            item_pipe={abilityType=0, time=0},
	            item_hood_of_defiance={abilityType=0, time=0}
	        },
	    isGlobal= false,
	    radius={50,50,50},
	    range={550,550,550}
	}

	Dodger.skillInfoMap['juggernaut_omni_slash'] = 
	{
	    item={  
	            item_lotus_orb={abilityType=1, time=0.15},
	            item_manta={abilityType=0,time=0.1},
	            item_ghost={abilityType=0, time=0.1},
	            item_manta={abilityType=0,time=0.08},
	            item_cyclone={abilityType=1, time=-0.1}, 
	        },
	    afterEffect = true,
	    isGlobal= false,
	    radius={50,50,50},
	    range={550,550,550}
	}
	Dodger.skillInfoMap['sven_storm_bolt'] = 
	{
	    item={  
	            item_lotus_orb={abilityType=1, time=0},
	            item_pipe={abilityType=0, time=0},
	            item_hood_of_defiance={abilityType=0, time=0},
	            item_cyclone={abilityType=1, time=0}, 
	        },
	    projectileItem ={
	    	item_manta={abilityType=0,time=0.08,range=200},
	    },
	    afterEffect = true,
	    isGlobal= false,
	    radius={50,50,50,50},
	    range={600,600,600,600}
	}

	Dodger.skillInfoMap['vengefulspirit_magic_missile'] = 
	{
	    item={  
	            item_lotus_orb={abilityType=1, time=0},
	            item_pipe={abilityType=0, time=0},
	            item_hood_of_defiance={abilityType=0, time=0},
	            item_cyclone={abilityType=1, time=0}, 
	        },
	    projectileItem ={
	    	item_manta={abilityType=0,time=0.08,range=300},
	    },
	    afterEffect = true,
	    isGlobal= false,
	    radius={50,50,50,50},
	    range={500,500,600,500}
	}

	Dodger.skillInfoMap['chaos_knight_chaos_bolt'] = 
	{
	    item={  
	            item_lotus_orb={abilityType=1, time=0},
	            item_pipe={abilityType=0, time=0},
	            item_hood_of_defiance={abilityType=0, time=0},
	            item_cyclone={abilityType=1, time=0}, 
	        },
	    projectileItem ={
	    	item_manta={abilityType=0,time=0.08,range=300},
	    },
	    afterEffect = true,
	    isGlobal= false,
	    radius={50,50,50,50},
	    range={500,500,600,500}
	}

	Dodger.skillInfoMap['skeleton_king_hellfire_blast'] = 
	{
	    item={  
	            item_lotus_orb={abilityType=1, time=0},
	            item_pipe={abilityType=0, time=0},
	            item_hood_of_defiance={abilityType=0, time=0},
	            item_cyclone={abilityType=1, time=0}, 
	        },
	    projectileItem ={
	    	item_manta={abilityType=0,time=0.08,range=300},
	    },
	    afterEffect = true,
	    isGlobal= false,
	    radius={50,50,50,50},
	    range={500,500,600,500}
	}

	Dodger.skillInfoMap['viper_viper_strike'] = 
	{
	    item={  
	            item_lotus_orb={abilityType=1, time=0},
	            item_pipe={abilityType=0, time=0},
	            item_hood_of_defiance={abilityType=0, time=0},
	            item_cyclone={abilityType=1, time=0}, 
	        },
	    projectileItem ={
	    	item_manta={abilityType=0,time=0.08,range=400},
	    },
	    afterEffect = true,
	    isGlobal= false,
	    radius={50,50,50,50},
	    range={400,400,400,400}
	}
	Dodger.skillInfoMap['winter_wyvern_winters_curse'] = 
	{
	    item={  
	            item_lotus_orb={abilityType=1, time=0.15},
	            item_ghost={abilityType=0, time=0.1}
	        },
	    isGlobal= false,
	    radius={500,500,500},
	    range={800,800,800}
	}

	Dodger.skillInfoMap['dragon_knight_dragon_tail'] = 
	{
	    item={  
	            item_lotus_orb={abilityType=1, time=0},
	            item_pipe={abilityType=0, time=0},
	            item_hood_of_defiance={abilityType=0, time=0},
	            item_cyclone={abilityType=1, time=0}, 
	        },
	    projectileItem ={
	    	item_manta={abilityType=0,time=0.08,range=400},
	    },
	    afterEffect = true,
	    isGlobal= false,
	    radius={50,50,50,50},
	    range={400,400,400,400}
	}

	Dodger.skillInfoMap['centaur_hoof_stomp'] = 
	{
	    item={  
	            item_manta={abilityType=0,time=0.1},
	            item_cyclone={abilityType=1, time=0.2}
	        },
	    isGlobal= false,
	    radius={315,315,315,315},
	    range={0,0,0,0}
	}
	
end

Dodger.projectileSkillMap ={
	sven_spell_storm_bolt="sven_storm_bolt",
	vengeful_magic_missle="vengefulspirit_magic_missile",
	chaos_knight_chaos_bolt = "chaos_knight_chaos_bolt",
	skeletonking_hellfireblast = "skeleton_king_hellfire_blast",
	UNKNOWN_RESOURCE="viper_viper_strike",
	dragon_knight_dragon_tail_dragonform_proj="dragon_knight_dragon_tail"
}
Dodger.skillProjectileMap ={}

Dodger.animationHeroMapData ={
    zeus_cast4_thundergods_wrath ={"npc_dota_hero_zuus",5},
    cast5_earth_splitter_anim = {"npc_dota_hero_elder_titan",5},
    attack_omni_cast = {"npc_dota_hero_juggernaut",5},
    chakram_anim = {"npc_dota_hero_shredder",5},
    cast_guardianAngel_anim = {"npc_dota_hero_omniknight",5},
    legion_commander_press_anim = {"npc_dota_hero_legion_commander",5},
    cast4_infest = {"npc_dota_hero_life_stealer",5},
    au_cast04_dark_rift={"npc_dota_hero_abyssal_underlord",5},
    pudge_dismember_start={"npc_dota_hero_pudge",5},
    echo_slam_anim={"npc_dota_hero_earthshaker",5},
    culling_blade_anim={"npc_dota_hero_axe",5},
    amp_anim={"npc_dota_hero_slardar",5},
    cast_doom_anim={"npc_dota_hero_doom_bringer",5},
    cast5_Overgrowth_anim={"npc_dota_hero_treant",5},
    sand_king_epicast_anim={"npc_dota_hero_sand_king",5},
    phantasm_anim={"npc_dota_hero_chaos_knight",5},
    ravage_anim={"npc_dota_hero_tidehunter",5},
    ultimate_anim={"npc_dota_hero_spirit_breaker",5,"npc_dota_hero_shadow_demon",5},
    Split_anim={"npc_dota_hero_brewmaster",5},
    polarity_anim={"npc_dota_hero_magnataur",5},
    death_pact_anim={"npc_dota_hero_clinkz",5},
    viper_strike_anim={"npc_dota_hero_viper",5},
    cast_4_poison_nova_anim={"npc_dota_hero_venomancer",5},
    cast4_tricks_trade={"npc_dota_hero_riki",5},
    cast4_rupture_anim={"npc_dota_hero_bloodseeker",5},
    trap_set_anim={"npc_dota_hero_templar_assassin",5},
    cast4_sirenSong_anim={"npc_dota_hero_naga_siren",5},
    sunder={"npc_dota_hero_terrorblade",5},
    cast_anim={"npc_dota_hero_antimage",5},
    cast4_gyroshell_cast_short={"npc_dota_hero_pangolier",5},
    cast_ulti_anim={"npc_dota_hero_weaver",5,"npc_dota_hero_obsidian_destroyer", 5, "npc_dota_hero_necrolyte",5},
    broodmother_cast4_hunger_anim={"npc_dota_hero_broodmother",5},
    chronosphere_anim={"npc_dota_hero_faceless_void",5},
    cast_tracker_anim={"npc_dota_hero_bounty_hunter",5},
    luna_eclipse_anim={"npc_dota_hero_luna",5},
    rearm_3_anim={"npc_dota_hero_tinker",5},
    rearm_2_anim={"npc_dota_hero_tinker",5},
    rearm_1_anim={"npc_dota_hero_tinker",5},
    cast_ability_4_anim={"npc_dota_hero_furion",5},
    cast_ability_6={"npc_dota_hero_keeper_of_the_light",5},
    skywrath_mage_mystic_flare_cast_anim = {"npc_dota_hero_skywrath_mage",5},
    cast04_winters_curse_flying_low_anim = {"npc_dota_hero_winter_wyvern",5},
    cast04_winters_curse_flying = {"npc_dota_hero_winter_wyvern",5},
    death_ward_anim = {"npc_dota_hero_witch_doctor",5},
    chain_frost_anim = {"npc_dota_hero_lich",5},
    cast5_coil_anim = {"npc_dota_hero_puck",5},
    life_drain_anim = {"npc_dota_hero_pugna",5},
    cast4_weave_anim = {"npc_dota_hero_dazzle",5},
    cast_mass_serpent_ward_anim ={"npc_dota_hero_shadow_shaman",5},
    warlock_cast4_rain_chaos_anim = {"npc_dota_hero_warlock",5},
    macropyre={"npc_dota_hero_jakiro",5},
    cast4_exorcism_anim={"npc_dota_hero_death_prophet",5},
    freezing_field_anim_10s = {"npc_dota_hero_crystal_maiden",5},
    cast_GS_anim = {"npc_dota_hero_silencer",5},
    queen_sonicwave_anim={"npc_dota_hero_queenofpain",5},
    cast4_False_Promise_anim= {"npc_dota_hero_oracle",5},
    fiends_grip_cast_anim={"npc_dota_hero_bane",5},
    laguna_blade_anim={"npc_dota_hero_lina",5},
    finger_anim={"npc_dota_hero_lion",5},
    lasso_start_anim = {"npc_dota_hero_batrider",5},
    cast4_black_hole_anim = {"npc_dota_hero_enigma",5},
    aa_iceblast_anim = {"npc_dota_hero_ancient_apparition",5},
    cast5_fear = {"npc_dota_hero_dark_willow",5},
    cast5_handofgod_anim = {"npc_dota_hero_chen", 5},
    Roll_pre = {"npc_dota_hero_storm_spirit",5},
    impetus_anim = {"npc_dota_hero_enchantress",5},
    wall_anim = {"npc_dota_hero_dark_seer",5}
}

Dodger.defendSkills={
	naga_siren_mirror_image=true
}
return Dodger