require("hs.ipc")

local drawing = require("hs.drawing")
local styledtext = require("hs.styledtext")
local timer = require("hs.timer")

local activeMonitAlerts = {}

local monitAlertStyle = {
  width = 336,
  minHeight = 64,
  maxHeight = 220,
  padding = 12,
  margin = 16,
  gap = 10,
  radius = 12,
  fadeInDuration = 0.12,
  fadeOutDuration = 0.25,
  duration = 4,
  backgroundAlpha = 0.9,
  textFont = ".AppleSystemUIFont",
  textSize = 13,
}

local function themeRoot()
  return os.getenv("STOW_DIR") or (os.getenv("HOME") .. "/.dots")
end

local function activeGhosttyThemePath()
  return themeRoot() .. "/themes/active/ghostty"
end

local function readActiveTerminalBackground()
  local file = io.open(activeGhosttyThemePath(), "r")
  if not file then
    return "#2e3440"
  end

  for line in file:lines() do
    local background = line:match("^%s*background%s*=%s*(#?[%da-fA-F]+)")
    if background then
      file:close()
      return background
    end
  end

  file:close()
  return "#2e3440"
end

local function hexToRgb(hex)
  hex = hex:gsub("#", "")
  if #hex == 3 then
    hex = hex:gsub("(.)", "%1%1")
  end

  return {
    red = tonumber(hex:sub(1, 2), 16) / 255,
    green = tonumber(hex:sub(3, 4), 16) / 255,
    blue = tonumber(hex:sub(5, 6), 16) / 255,
  }
end

local function linearColor(value)
  if value <= 0.03928 then
    return value / 12.92
  end

  return ((value + 0.055) / 1.055) ^ 2.4
end

local function relativeLuminance(color)
  return 0.2126 * linearColor(color.red) + 0.7152 * linearColor(color.green) + 0.0722 * linearColor(color.blue)
end

local function activeMonitTheme()
  local background = hexToRgb(readActiveTerminalBackground())
  background.alpha = monitAlertStyle.backgroundAlpha

  local isDarkBackground = relativeLuminance(background) < 0.45
  local text = isDarkBackground and { white = 1, alpha = 1 } or { white = 0, alpha = 1 }
  local stroke = isDarkBackground and { white = 1, alpha = 0.18 } or { white = 0, alpha = 0.18 }
  local highlight = isDarkBackground and { red = 1, green = 0.42, blue = 0.42, alpha = 1 } or { red = 0.72, green = 0, blue = 0.08, alpha = 1 }

  return {
    backgroundColor = background,
    textColor = text,
    strokeColor = stroke,
    highlightColor = highlight,
  }
end

local function activeAlertIndex(alert)
  for index, candidate in ipairs(activeMonitAlerts) do
    if candidate == alert then
      return index
    end
  end
  return nil
end

local function removeMonitAlert(alert)
  local index = activeAlertIndex(alert)
  if index then
    table.remove(activeMonitAlerts, index)
  end

  for _, item in ipairs(alert.drawings) do
    item:hide(monitAlertStyle.fadeOutDuration)
    timer.doAfter(monitAlertStyle.fadeOutDuration, function()
      item:delete()
    end)
  end
end

local function nextAlertYOffset()
  local offset = 0
  for _, alert in ipairs(activeMonitAlerts) do
    offset = offset + alert.height + monitAlertStyle.gap
  end
  return offset
end

local function capitalized(value)
  value = value or "process"
  return value:sub(1, 1):upper() .. value:sub(2)
end

local function normalizedMonitInput(title, subtitle, message)
  return title or "Monit alert", subtitle or "", (message or ""):gsub("\\n", "\n")
end

local function matchedProcessFrom(message)
  return message:match("matched%s+'([^']+)'") or message:match("matched%s+(.+)%s+exceeded") or "unknown"
end

local function exceededSummaryFrom(message)
  return message:match("exceeded%s+([^\n]+)") or "threshold exceeded"
end

local function cpuSummaryFrom(subtitle)
  return subtitle:match("CPU%s+[%d.]+%%") or "CPU ?%"
end

local function serviceNameFrom(title)
  return capitalized(title:match("High CPU:%s*(.+)") or "process")
end

local function monitBody(title, subtitle, message)
  local normalizedTitle, normalizedSubtitle, normalizedMessage = normalizedMonitInput(title, subtitle, message)
  local serviceName = serviceNameFrom(normalizedTitle)
  local matchedProcess = matchedProcessFrom(normalizedMessage):gsub("Browser", "browser")
  local cpuSummary = cpuSummaryFrom(normalizedSubtitle)
  local exceededSummary = exceededSummaryFrom(normalizedMessage)

  return string.format(
    "%s (matched: %s)\n%s, exceeded %s",
    serviceName,
    matchedProcess,
    cpuSummary,
    exceededSummary
  )
end

local function measuredLineHeight()
  local size = drawing.getTextDrawingSize("Hg", { font = monitAlertStyle.textFont, size = monitAlertStyle.textSize })
  return math.ceil((size and size.h or monitAlertStyle.textSize) * 1.1)
end

local function measuredWrappedLineCount(line, usableWidth)
  if line == "" then
    return 1
  end

  local size = drawing.getTextDrawingSize(line, { font = monitAlertStyle.textFont, size = monitAlertStyle.textSize })
  local width = size and size.w or 0
  return math.max(1, math.ceil(width / usableWidth))
end

local function estimatedAlertHeight(body)
  local usableWidth = monitAlertStyle.width - monitAlertStyle.padding * 2
  local lineHeight = measuredLineHeight()
  local bodySize = drawing.getTextDrawingSize(body, { font = monitAlertStyle.textFont, size = monitAlertStyle.textSize })
  local measuredHeight = bodySize and bodySize.h or monitAlertStyle.minHeight
  local extraWrappedLines = 0

  for line in (body .. "\n"):gmatch("(.-)\n") do
    extraWrappedLines = extraWrappedLines + measuredWrappedLineCount(line, usableWidth) - 1
  end

  local estimatedHeight = math.ceil(measuredHeight + extraWrappedLines * lineHeight + monitAlertStyle.padding * 2 + 4)
  return math.max(monitAlertStyle.minHeight, math.min(monitAlertStyle.maxHeight, estimatedHeight))
end

local function boldRange(textObject, starts, ends, color)
  if not starts then
    return textObject
  end

  local boldFont = styledtext.convertFont({ name = monitAlertStyle.textFont, size = monitAlertStyle.textSize }, true)
  return textObject:setStyle({ font = boldFont, color = color }, starts, ends)
end

local function monitStyledText(body, textColor, highlightColor)
  local baseStyle = {
    font = { name = monitAlertStyle.textFont, size = monitAlertStyle.textSize },
    color = textColor,
    paragraphStyle = {
      alignment = "left",
      lineBreak = "wordWrap",
    },
  }
  local textObject = styledtext.new(body, baseStyle)

  local cpuStart, cpuEnd = body:find("CPU%s+[%d.]+%%")
  textObject = boldRange(textObject, cpuStart, cpuEnd, highlightColor)

  local matchedLabel = "matched: "
  local matchedProcessStart = body:find(matchedLabel, 1, true)
  if matchedProcessStart then
    local processStart = matchedProcessStart + #matchedLabel
    local processEnd = body:find(")", processStart, true)
    if processEnd then
      textObject = boldRange(textObject, processStart, processEnd - 1, highlightColor)
    end
  end

  return textObject
end

function monitNotify(title, subtitle, message)
  local theme = activeMonitTheme()
  local screenFrame = hs.screen.mainScreen():frame()
  local body = monitBody(title, subtitle, message)
  local alertHeight = estimatedAlertHeight(body)
  local frame = {
    x = screenFrame.x + screenFrame.w - monitAlertStyle.width - monitAlertStyle.margin,
    y = screenFrame.y + monitAlertStyle.margin + nextAlertYOffset(),
    w = monitAlertStyle.width,
    h = alertHeight,
  }
  local textFrame = {
    x = frame.x + monitAlertStyle.padding,
    y = frame.y + monitAlertStyle.padding,
    w = frame.w - monitAlertStyle.padding * 2,
    h = frame.h - monitAlertStyle.padding * 2,
  }
  local styledBody = monitStyledText(body, theme.textColor, theme.highlightColor)

  local background = drawing.rectangle(frame)
    :setFill(true)
    :setFillColor(theme.backgroundColor)
    :setStroke(true)
    :setStrokeColor(theme.strokeColor)
    :setStrokeWidth(1)
    :setRoundedRectRadii(monitAlertStyle.radius, monitAlertStyle.radius)
    :bringToFront(false)
    :show(monitAlertStyle.fadeInDuration)

  local text = drawing.text(textFrame, styledBody)
    :orderAbove(background)
    :show(monitAlertStyle.fadeInDuration)

  local alert = { drawings = { background, text }, height = alertHeight }
  table.insert(activeMonitAlerts, alert)

  timer.doAfter(monitAlertStyle.duration, function()
    removeMonitAlert(alert)
  end)
end
