async function fillGreetings(customClientWidgets, key) {
  document.querySelectorAll("div .information-widget-greeting span")
    .forEach(el => {
      if (el?.doNotNeedProcess || !/\${.*}/.test(el.innerText)) {
        el.doNotNeedProcess = true;
        return
      }
      if (!(new RegExp("\\${" + key + ".*}")).test(el.innerText))
        return
      el.innerText = (new Function("customClientWidgets", `
        with (customClientWidgets) {
          return \`${el.innerText}\`
        }
      `))(customClientWidgets)
    })
}

async function main() {
  const customClientWidgets = new Proxy({}, {
    async set (target, key, value) {
      target[key] = value
      fillGreetings(target, key)
      return true
    }
  })

  populateCustomClientWidgetsData(customClientWidgets)
}

main()
