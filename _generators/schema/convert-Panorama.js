// To execute:
//
// node Panorama.js > panorama.json
//
// Path to Panorama.javascript: https://${panorama}/php/misc/namedschema/Panorama.javascript

class Ext {
  static ns(x){
  }
}

class Pan {
  constructor(){
    var _schema=null;
  }
}

const fs = require('fs')

fs.readFile('./Panorama.javascript', 'utf8' , (err, data) => {
  if (err) {
    console.error(err)
    return
  }
  eval(data)

  str = JSON.stringify(Pan._schema, null, 2);
  console.log(str);
})

