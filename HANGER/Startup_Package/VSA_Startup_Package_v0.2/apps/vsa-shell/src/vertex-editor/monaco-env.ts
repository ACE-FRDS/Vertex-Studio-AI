import E from'monaco-editor/esm/vs/editor/editor.worker?worker'
import J from'monaco-editor/esm/vs/language/json/json.worker?worker'
import C from'monaco-editor/esm/vs/language/css/css.worker?worker'
import H from'monaco-editor/esm/vs/language/html/html.worker?worker'
import T from'monaco-editor/esm/vs/language/typescript/ts.worker?worker'
;(self as unknown as{MonacoEnvironment:{getWorker:(_m:string,l:string)=>Worker}}).MonacoEnvironment={getWorker(_m,l){if(l==='json')return new J();if(['css','scss','less'].includes(l))return new C();if(['html','handlebars','razor'].includes(l))return new H();if(['typescript','javascript'].includes(l))return new T();return new E()}}