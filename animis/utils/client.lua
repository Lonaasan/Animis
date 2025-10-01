---animis client utilities
---Author: Lonaasan
string.animis = string.animis or {};
string.animis.client = string.animis.client or {};

animis_client = {}

---Check if we are running with Neon++
---@return boolean
function animis_client.isNeon()
    return neon ~= nil;
end

---Check if we are running with StarExtensions
---@return boolean
function animis_client.isStarExtensions()
    return starExtensions ~= nil;
end

---Check if we are running in OpenStarbound
---@return boolean
function animis_client.isOpenStarbound()
    return root.assetJson("/player.config:genericScriptContexts").OpenStarbound ~= nil;
end

---Check if we are running in XStarbound
---@return boolean
function animis_client.isXStarbound()
    return xsb ~= nil;
end

---Check if we are running in Vanilla
---@return boolean
function animis_client.isVanilla()
    return
        not animis_client.isNeon() and not animis_client.isStarExtensions() and not animis_client.isOpenStarbound() and
            not animis_client.isXStarbound();
end

--- Get the client object for the current environment
---@return string
function animis_client.getClient()
    if animis_client.isNeon() then
        return "Neon";
    elseif animis_client.isStarExtensions() then
        return "StarExtensions";
    elseif animis_client.isXStarbound() then
        -- reverse order to circumvent XStarbound's disguise as OpenStarbound.
        -- This way we check for xSB features, which are not in oSB.
        return "XStarbound";
    elseif animis_client.isOpenStarbound() then
        return "OpenStarbound";
    else
        return "Vanilla";
    end
end

--- Export the functions for 3rd parties to use without the possibility of changing the original code
string.animis.client = animis_client;
